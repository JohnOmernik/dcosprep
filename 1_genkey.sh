#!/bin/bash
HOSTFILE="./hostlist.txt"

HOSTS=$(cat $HOSTFILE)

INIT_KEY="~/.ssh/id_rsa"
INIT_USER="ubuntu"
GEN_KEY="Y"
echo "Generating new Key for use on cluster"
if [ -f "./out.prv" ]; then
    echo "Private Key already identified in directory"
    read -e -p "Regenertate New Private/Public Key Pair? " -i "N" GEN_KEY
fi

if [ "$GEN_KEY" == "Y" ]; then
    rm -rf out.prv
    rm -rf out.prv.pub
    ssh-keygen -f ./out.prv -N "" -t RSA -C "DCOS"
fi

PUB=$(cat out.prv.pub)

ZETA_ID="2500"
MAPR_ID="2000"


# Ask the user for the passwords for the mapr and zetaadm users
echo ""
echo "--------------------------------------------------"
####################
###### ADD zetaadm user and sync passwords on mapr User
echo "Prior to installing Zeta, there are two steps that must be taken to ensure two users exist and are in sync across the nodes"
echo "The two users are:"
echo ""
echo "mapr - This user is installed by the mapr installer and used for mapr services, however, we need to change the password and sync the password across the nodes"
echo "zetaadm - This is the user you can use to administrate your cluster and install packages etc."
echo ""
echo "Please keep track of these users' passwords"
echo ""
echo ""

# TODO: remove this first question and rely on the while statement to ask the questions
echo "Syncing mapr password on all nodes"
stty -echo
printf "Please enter new password for mapr user on all nodes: "
read mapr_PASS1
echo ""
printf "Please re-enter password for mapr: "
read mapr_PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$mapr_PASS1" != "$mapr_PASS2" ]
do
    echo "Passwords entered for mapr user do not match, please try again"
    stty -echo
    printf "Please enter new password for mapr user on all nodes: "
    read mapr_PASS1
    echo ""
    printf "Please re-enter password for mapr: "
    read mapr_PASS2
    echo ""
    stty echo
done

# TODO: remove this first question and rely on the while statement to ask the questions
echo ""
echo "Adding user zetaadm to all nodes"
stty -echo
printf "Please enter the zetaadm Password: "
read zetaadm_PASS1
echo ""

printf "Please re-enter the zetaadm Password: "
read zetaadm_PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$zetaadm_PASS1" != "$zetaadm_PASS2" ]
do
    echo "Passwords for zetaadm do not match, please try again"
    echo ""
    stty -echo
    printf "Please enter the zetaadm Password: "
    read zetaadm_PASS1
    echo ""

    printf "Please re-enter the zetaadm Password: "
    read zetaadm_PASS2
    echo ""
    stty echo
done




# Create the script that will be executed on each machine to add the users
echo ""
echo "Creating User Update Script"

SCRIPT="/tmp/userupdate.sh"
SCRIPTSRC="./userupdate.sh"

cat > $SCRIPTSRC << EOF
#!/bin/bash

sudo sed -i "s/Defaults    requiretty//g" /etc/sudoers
sudo sed -i "s/Defaults   \!visiblepw//g" /etc/sudoers

DIST_CHK=\$(egrep -i -ho 'ubuntu|redhat|centos' /etc/*-release | awk '{print toupper(\$0)}' | sort -u)
UB_CHK=\$(echo \$DIST_CHK|grep UBUNTU)
RH_CHK=\$(echo \$DIST_CHK|grep REDHAT)
CO_CHK=\$(echo \$DIST_CHK|grep CENTOS)

if [ "\$UB_CHK" != "" ]; then
    INST_TYPE="ubuntu"
    echo "Ubuntu"
elif [ "\$RH_CHK" != "" ] || [ "\$CO_CHK" != "" ]; then
    INST_TYPE="rh_centos"
    echo "Redhat"
else
    echo "Unknown lsb_release -a version at this time only ubuntu, centos, and redhat is supported"
    echo \$DIST_CHK
    exit 1
fi

echo "\$INST_TYPE"

if [ "\$INST_TYPE" == "ubuntu" ]; then
   adduser --disabled-login --gecos '' --uid=$ZETA_ID zetaadm
   adduser --disabled-login --gecos '' --uid=$MAPR_ID mapr
   echo "zetaadm:$zetaadm_PASS1"|chpasswd
   echo "mapr:$mapr_PASS1"|chpasswd
elif [ "\$INST_TYPE" == "rh_centos" ]; then
   adduser --uid $ZETA_ID zetaadm
   adduser --uid $MAPR_ID mapr
   echo "$zetaadm_PASS1"|passwd --stdin zetaadm
   echo "$mapr_PASS1"|passwd --stdin mapr
else
    echo "Relase not found, not sure why we are here, exiting"
    exit 1
fi
Z=\$(sudo grep zetaadm /etc/sudoers)
M=\$(sudo grep mapr /etc/sudoers)

if [ "\$Z" == "" ]; then
    echo "Adding zetaadm to sudoers"
    echo "zetaadm ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi
if [ "\$M" == "" ]; then
    echo "Adding mapr to sudoers"
    echo "mapr ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi
EOF

chmod 700 $SCRIPTSRC

# Copy the script over to each node and execute it, removing it after the work is done
# TODO: Verify that the script worked on each node?



HSTCNT=0
for HOST in $HOSTS; do
    HSTCNT=$(( $HSTCNT + 1 ))
    echo "Connecing to host $HOST"
    echo ""
    echo "Copying User Update Script"
    scp -o StrictHostKeyChecking=no -i ${INIT_KEY} ${SCRIPTSRC} ${INIT_USER}@${HOST}:$SCRIPT
    echo "Updating Permissions on Script"
    ssh -o StrictHostKeyChecking=no -i ${INIT_KEY} ${INIT_USER}@$HOST "chmod 700 $SCRIPT"
    echo "Running Script" 
    ssh -o StrictHostKeyChecking=no -t -i ${INIT_KEY} ${INIT_USER}@$HOST "sudo $SCRIPT"
    echo "Removing Script"
    ssh -o StrictHostKeyChecking=no -i ${INIT_KEY} ${INIT_USER}@$HOST "sudo rm $SCRIPT"
    echo "Updating Public Key for Zetaadm user"
    ssh -o StrictHostKeyChecking=no -i ${INIT_KEY} ${INIT_USER}@$HOST "sudo mkdir -p /home/zetaadm/.ssh && echo \"$PUB\"|sudo tee -a /home/zetaadm/.ssh/authorized_keys && sudo chown -R zetaadm:zetaadm /home/zetaadm/.ssh && sudo chmod 700 /home/zetaadm/.ssh && sudo chmod 600 /home/zetaadm/.ssh/authorized_keys"
    INTER_IP=$(ssh -o StrictHostKeyChecking=no -i ${INIT_KEY} ${INIT_USER}@$HOST "source /etc/profile && ip addr show eth0 | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1")
    echo $INTER_IP >> ./internal_hosts.txt

  if [ "$HSTCNT" == "1" ]; then
        echo "This is initial host"
        echo ""
        echo "Copying and securing creds.txt"
        ssh -o StrictHostKeyChecking=no -i ./out.prv zetaadm@${HOST} "mkdir /home/zetaadm/creds"
        ssh -o StrictHostKeyChecking=no -i ./out.prv zetaadm@${HOST} "chmod 700 /home/zetaadm/creds"
cat > ./creds.txt << EOC
zetaadm:${zetaadm_PASS1}
mapr:${mapr_PASS1}
EOC
        scp -o StrictHostKeyChecking=no -i ./out.prv ./creds.txt zetaadm@${HOST}:/home/zetaadm/creds/creds.txt
        ssh -o StrictHostKeyChecking=no -i ./out.prv  zetaadm@${HOST} "chmod 600 /home/zetaadm/creds/creds.txt"
        echo "Copying Private key to initial host"
        scp -o StrictHostKeyChecking=no -i ./out.prv ./out.prv zetaadm@${HOST}:/home/zetaadm/.ssh/id_rsa
        INIT_HOST=$HOST
        echo "Removing creds"
        rm ./creds.txt
  fi

done
scp -o StrictHostKeyChecking=no -i ./out.prv ./internal_hosts.txt zetaadm@${INIT_HOST}:/home/zetaadm/

rm $SCRIPTSRC

echo "zetaadm and mapr users created on all hosts in $HOSTFILE"
echo "One host was selected as the Initial Hosts, it has a copy of the private key, it's recommended you do next steps from that hose"
echo "Init Host: $INIT_HOST"

echo "Connect via: ssh -i ./out.prv zetaadm@${INIT_HOST}"














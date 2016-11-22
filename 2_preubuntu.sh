#!/bin/bash


HOSTS=$(cat ./hostlist.txt)

cat > ./u_prep.sh << EOF2
#!/bin/bash

echo "Ensure AWS Security Groups allow Node to Node Communications"


echo "Cleaning rc.local"
sudo sed -i "s/exit 0//g" /etc/rc.local

echo "Disabling Plymouth"
echo "/bin/rm -f /etc/init.d/plymouth* > /dev/null 2>&1"  | sudo tee -a /etc/rc.local

sudo apt-get update
sudo apt-get upgrade -y -o Dpkg::Options::="--force-confold"
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main"|sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get dist-upgrade -y

sudo apt-get purge lxc-docker
sudo apt-get remove -y command-not-found

sudo mkdir -p /etc/systemd/system/docker.service.d && sudo tee /etc/systemd/system/docker.service.d/override.conf <<- EOF
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay -H fd://

EOF
#ExecStart=/usr/bin/docker daemon --storage-driver=overlay --insecure-registry=maprdocker-mapr-shared.marathon.slave.mesos:5000 --insecure-registry=dockerregv2-shared.marathon.slave.mesos:5005 -H fd://

sudo apt-get install -y -q docker-engine=1.11.2-0~xenial
#sudo apt-get install -y -q docker-engine




sudo systemctl enable docker

sudo apt-get install -y ipset unzip bc nfs-common syslinux

sudo ln -s /bin/mkdir /usr/bin/mkdir
sudo ln -s /bin/ln /usr/bin/ln
sudo ln -s /bin/tar /usr/bin/tar
sudo ln -s /bin/rm /usr/bin/rm
sudo ln -s /usr/sbin/useradd /usr/bin/useradd

echo "DefaultTasksMax=infinity"|sudo tee -a /etc/systemd/system.conf


# Check for /mnt in fstab
CHK=\$(sudo grep "\/mnt" /etc/fstab|cut -f1)
if [ "\$CHK" != "" ]; then
    echo "Updating weird mount of /mnt"
    sudo sed -i "s@\$CHK@#\$CHK@" /etc/fstab
fi



sudo shutdown -r now
EOF2

chmod +x ./u_prep.sh


for H in $HOSTS; do
    echo "Running on host $H"
    scp -i ./out.prv ./u_prep.sh zetaadm@$H:/home/zetaadm/
    ssh -i ./out.prv zetaadm@$H "chmod +x /home/zetaadm/u_prep.sh && /home/zetaadm/u_prep.sh"
done


rm ./u_prep.sh

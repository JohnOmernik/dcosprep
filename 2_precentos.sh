#!/bin/bash


HOSTS=$(cat ./hostlist.txt)

cat > ./c_prep1.sh << EOF2
#!/bin/bash

. /etc/profile

echo "Ensure AWS Security Groups allow Node to Node Communications"

sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

sudo yum install http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm --assumeyes --tolerant

sudo yum --enablerepo=elrepo-kernel install kernel-ml --assumeyes --tolerant

sudo yum upgrade --assumeyes --tolerant

sudo yum update --assumeyes


sudo sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/sysconfig/selinux
sudo sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
sudo groupadd -g 350 nogroup



MENU_ITM=\$(sudo cat /boot/grub2/grub.cfg|grep "menuentry "|grep -n "Linux .4\."|cut -d":" -f1)

NEWMENU=\$((\$MENU_ITM - 1))

sudo grub2-set-default \$NEWMENU

O_CHECK=\$(lsmod | grep overlay)

if [ "\$O_CHECK" == "" ]; then
    echo "Overlay not loaded, adding and rebooting"
sudo tee /etc/modules-load.d/overlay.conf <<-'EOF3'
overlay
EOF3
else
    echo "Overlay already installed, not rebooting"
fi
sudo shutdown -r now
EOF2


cat > ./c_prep2.sh << EOF4
#!/bin/bash

. /etc/profile

sudo tee /etc/yum.repos.d/docker.repo <<-'EOF5'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF5

sudo mkdir -p /etc/systemd/system/docker.service.d && sudo tee /etc/systemd/system/docker.service.d/override.conf <<- EOF6
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay --insecure-registry=maprdocker-mapr-shared.marathon.slave.mesos:5000 --insecure-registry=dockerregv2-shared.marathon.slave.mesos:5005 -H fd://
EOF6


sudo yum install -y docker-engine-1.11.2
sudo systemctl start docker
sudo systemctl enable docker


sudo yum  install -y ipset unzip bc nfs-common syslinux nano git

echo ""
# Check for /mnt in fstab
CHK=\$(sudo grep "\/mnt" /etc/fstab|cut -f1)
if [ "\$CHK" != "" ]; then
    echo "Updating weird mount of /mnt"
    sudo sed -i "s@\$CHK@#\$CHK@" /etc/fstab
fi
echo ""
echo "Rebooting"



sudo shutdown -r now
EOF4


chmod +x ./c_prep1.sh
chmod +x ./c_prep2.sh


for H in $HOSTS; do
    echo "Running Script 1 on host $H"
    scp -i ./out.prv ./c_prep1.sh zetaadm@$H:/home/zetaadm/
    scp -i ./out.prv ./c_prep2.sh zetaadm@$H:/home/zetaadm/
    ssh -i ./out.prv zetaadm@$H "chmod +x /home/zetaadm/c_prep1.sh && /home/zetaadm/c_prep1.sh"
done

sleep 10

for H in $HOSTS; do

    echo "Running Script 2 on host $H"
    ssh -i ./out.prv zetaadm@$H "chmod +x /home/zetaadm/c_prep2.sh && /home/zetaadm/c_prep2.sh"
done

rm ./c_prep1.sh
rm ./c_prep2.sh





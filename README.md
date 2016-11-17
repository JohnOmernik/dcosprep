# dcosprep
## Scripts to setup DCOS on Ubuntu and CentOS for Zeta
----------
This repo is designed to help get DCOS setup and ready to go via the Advanced Install.  Right now it works on Ubuntu 16.04 and CentOS 7.0. And is really angled at AWS. 

To start, you run this from system that has the private key for the AWS servers, you don't run this from the AWS servers themselves. 

So, steps:

- Start some instances (I was using M3 or D2)
- Ensure that all nodes can talk to each other on all ports (all traffic to your AWS subnet)
- Ensure you can talk to your nodes on all ports (I use my ip)
- When I did CentOS, the AMI didn't attach the instance stores, I had to manually do that in the instance creations... 
- Once your instances are up, put the public IPs, one per line in a file called hostlist.txt 
- run 1_genkey.sh It will create users (zetaadm and mapr) on all nodes, and create a new pub/prv key to use for zetaadm. (saved as out.prv and out.prv.pub in the working dir)
- Then run 2_precentos.sh or 2_preubuntu.sh depending on the node type you picked. This will update things, install latest kernels, install Docker etc. Get everything ready. 

At this point you need to move to the advanced install of DCOS. https://dcos.io/docs/1.8/administration/installing/custom/advanced/  What I did with some examples is here

On your initial node (the first node in the hostlist.txt)  create a folder: 

mkdir -p ~/dcosboot/genconf

cd dcosboot

Create a file ./genconf/ip-detect
This is what I put it in it:

```
#!/bin/bash

INTS="eth0 em1 eno1 enp2s0 enp3s0 ens192"

for INT in $INTS; do
#    echo "Interface: $INT"
    T=$(ip addr|grep "$INT")
    if [ "$T" != "" ]; then
        MEIP=$(ip addr show $INT | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
        echo $MEIP
        break
    fi
done
```

chmod +x ~/dcosboot/genconf/ip-detect

then try running it make sure you get an internal IP back

Ok good Now, create a file called config.yaml under genconf

This is what I put in mine:

```
---
bootstrap_url: http://172.31.8.40:50091
cluster_name: mydcos
exhibitor_storage_backend: static
log_directory: /genconf/logs
master_discovery: static
telemetry_enabled: 'false'
master_list:
- 172.31.8.41
process_timeout: 120
resolvers:
- 172.31.0.2
dns_search: us-west-2.compute.internal
process_timeout: 300
oauth_enabled: 'false'
ssh_key_path: /home/zetaadm/.ssh/id_rsa
ssh_port: '22'
ssh_user: zetaadm
```

- For reference, in this case I had 3 nodes, 172.31.8.40, 172.31.8.41, 172.31.8.42.  172.31.8.40 was the internal IP of my initial node. So it's my bootstrap node. I picked 172.31.8.41 to be my master.  
- The resolvers were set by looking in /etc/resolv.conf makes sure it's accurate. 

I am not doing auth, you can change if you want. 

From here run the following 4 commands

```sudo docker pull nginx```

```curl -O https://downloads.dcos.io/dcos/stable/dcos_generate_config.sh```

```sudo bash dcos_generate_config.sh```

```sudo docker run -d -p 50091:80 -v `pwd`/genconf/serve:/usr/share/nginx/html:ro nginx```

Now you can start installing your nodes, first SSH to your master node (I will use my IPs as an example)

ssh 172.31.8.41

Then run:

mkdir -p /tmp/dcos && cd /tmp/dcos && curl -O http://172.31.8.40:50091/dcos_install.sh && sudo bash dcos_install.sh master


* Note: I have to put the IP of my bootstrap node form my config (and running the docker image) *

If you have other masters, go to them and do the same.

Then on any agents that are NOT your bootstrap node, after your master(s) are running, ssh to the slaves and run the command below.

ssh 172.31.8.42

mkdir -p /tmp/dcos && cd /tmp/dcos && curl -O http://172.31.11.132:50091/dcos_install.sh && sudo bash dcos_install.sh slave

Finally, if you want to use your bootstrap node as a DCOS agent, ssh there and run the following:

ssh 172.31.8.40

mkdir -p /tmp/dcos && cd /tmp/dcos && curl -O http://172.31.11.132:50091/dcos_install.sh && sed -i "s/systemctl restart docker/# systemctl restart docker/" dcos_install.sh && sudo bash dcos_install.sh slave

This installs the DCOS agent, but comments out a docker restart that kills the bootstrap server... it's a hack, but it works. 

Now you have a working DCOS install, and you can go on to maprdcos or other fun repos! 

https://github.com/JohnOmernik/maprdcos

#!/bin/bash

USER_NAME="jenkins-builder"
USER_PASSWD='Uos123!!'
uniontech_usrname='ut000110'
uniontech_pwd='wbh19661007,'

#安装必要依赖
sudo apt update
sudo apt install -y curl git sshpass openjdk-8-jdk

#ac上网认证
curl -X POST --url "http://ac.uniontech.com/ac_portal/login.php" \
  --header "content-type: application/x-www-form-urlencoded" \
  --data opr="pwdLogin" \
  --data userName="${uniontech_usrname}" \
  --data pwd="${uniontech_pwd}" \
  --data rememberPwd='0'

#系统激活
uos-activator-cmd -s --kms kms.uniontech.com:8900:Vlc1cGIyNTBaV05v


#下次启动自动进入pxe装机
pxe_boot=$(efibootmgr | grep "PXE" | awk -F "*" '{print $1}' | awk -F "Boot" '{print $2}')
echo ${USER_PASSWD} | sudo -S efibootmgr -n ${pxe_boot}

#不锁屏，不待机
gsettings set com.deepin.dde.power line-power-screen-black-delay 0
gsettings set com.deepin.dde.power battery-screen-black-delay 0

gsettings set com.deepin.dde.power line-power-sleep-delay 0
gsettings set com.deepin.dde.power battery-sleep-delay 0

gsettings set com.deepin.dde.power line-power-lock-delay 0
gsettings set com.deepin.dde.power battery-lock-delay 0

#主动连接节点
mkdir -p ${HOME}/workspace
cd ${HOME}/workspace && wget https://jenkinswh.uniontech.com/jnlpJars/agent.jar
chmod +x ${HOME}/workspace/agent.jar
ARCHNAME=$(dpkg-architecture -qDEB_HOST_ARCH)
if [ ${ARCHNAME} = "amd64" ];then
  java -jar agent.jar -jnlpUrl https://jenkinswh.uniontech.com/computer/builder-beijing-amd64-53.247/jenkins-agent.jnlp -secret 186696d9544d26d58bd98398fe2440e306271d7b1b43b8ac22b9931cee0782c5 -workDir "${HOME}/jenkins"
elif [ ${ARCHNAME} = "arm64" ];then
  echo "暂无"
elif [ ${ARCHNAME} = "mips64el" ];then
  java -jar agent.jar -jnlpUrl https://jenkinswh.uniontech.com/computer/builder-beijing-mips64-249/jenkins-agent.jnlp -secret 5a03539433e2ab236d60dc0b2f09aea8dfcc107022c9e1cd20468bbf435572fe -workDir "${HOME}/jenkins"
else
  echo "暂不支持该架构"
fi

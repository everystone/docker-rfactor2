# Container to be able to run an rFactor2 server (EXPERIMENTAL)
#
# It Contains:
# SSH server:  
# X server: The graphical user interface core. (xvfb + xdm)
# JWM desktop: The graphical desktop interface.
# VNC server: To access the desktop remotely. 
# Wine: Windows implementation to be able to install and run rFactor 2
# 
# Based on rogaha/docker-desktop and suchja/wine


FROM ubuntu:latest

ENV TZ=Europe/Oslo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


RUN apt-get update -y
RUN apt-get install -y openssh-server xdm xvfb jwm sudo xterm cabextract rox-filer x11vnc links


# Install some tools required for creating the image
RUN apt-get update -y \
	&& apt-get install -y --no-install-recommends \
		curl \
		unzip \
		software-properties-common


# steam cmd
RUN sudo add-apt-repository multiverse
RUN sudo dpkg --add-architecture i386
RUN  sudo apt update

RUN echo steam steam/license note '' | debconf-set-selections && \
    echo steam steam/question select 'I AGREE' | debconf-set-selections && \
    apt-get install --yes --install-recommends \
      steamcmd

#RUN wget https://dl.winehq.org/wine-builds/Release.key
#RUN apt-key add Release.key
#RUN apt-add-repository 'https://dl.winehq.org/wine-builds/ubuntu/'

# Install wine and related packages
# Define which versions we need
#ENV WINE_MONO_VERSION 4.5.6
#ENV WINE_GECKO_VERSION 2.40

#RUN dpkg --add-architecture i386 \
#	&& apt-get update -y \
#	&& apt-get install -y --no-install-recommends \
#		wine1.7 \
#		wine-gecko$WINE_GECKO_VERSION:i386 \
#		wine-gecko$WINE_GECKO_VERSION:amd64 \
#		wine-mono$WINE_MONO_VERSION \
#	&& rm -rf /var/lib/apt/lists/*
# install latest wine
RUN wget -qO- https://dl.winehq.org/wine-builds/Release.key | sudo apt-key add -
RUN sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv F987672F
RUN sudo apt-add-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ bionic main'
RUN apt-get update
RUN sudo apt-get install --install-recommends wine-stable-amd64 -y
RUN sudo apt-get install --install-recommends wine-stable winehq-stable -y

# Use the latest version of winetricks
RUN curl -SL 'https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks' -o /usr/local/bin/winetricks \
		&& chmod +x /usr/local/bin/winetricks


# Set the env variable DEBIAN_FRONTEND to noninteractive
ENV DEBIAN_FRONTEND noninteractive


# Configuring xdm to allow connections from any IP address and ssh to allow X11 Forwarding. 
RUN sed -i 's/DisplayManager.requestPort/!DisplayManager.requestPort/g' /etc/X11/xdm/xdm-config
RUN sed -i '/#any host/c\*' /etc/X11/xdm/Xaccess
RUN ln -s /usr/bin/Xorg /usr/bin/X
RUN echo X11Forwarding yes >> /etc/ssh/ssh_config

# Fix PAM login issue with sshd
RUN sed -i 's/session    required     pam_loginuid.so/#session    required     pam_loginuid.so/g' /etc/pam.d/sshd

# Upstart and DBus have issues inside docker. We work around in order to install firefox.
RUN dpkg-divert --local --rename --add /sbin/initctl && ln -sf /bin/true /sbin/initctl


# Set locale (fix the locale warnings)
RUN localedef -v -c -i en_US -f UTF-8 en_US.UTF-8 || :

# Copy the files into the container
ADD . /src

# Expose ssh, rfactor 2 web and simulation ports, and vnc port.
EXPOSE 22
EXPOSE 54297
EXPOSE 64297
EXPOSE 5900
# 
# Create the directory needed to run the sshd daemon
RUN mkdir /var/run/sshd 

# Download rFactor2 Lite Build 1036
#RUN cd /home/docker && wget http://www.mediafire.com/download/xdqvbzredm3z9z5/rFactor2_LiteBuild_1036.exe
#RUN cd /home/docker && wget http://media.steampowered.com/installer/steamcmd.zip
#run ls -l
#RUN unzip steamcmd.zip
#RUN ls
#RUN apt-get install steamcmd
#RUN sudo su - steam
RUN /usr/games/steamcmd +@sSteamCmdForcePlatformType windows +login anonymous +force_install_dir /usr/local/rf2 +app_update 400300 +quit
#RUN chown docker:docker /home/docker/*.exe
RUN ls

# Add docker user and generate a random password with 12 characters that includes at least one capital letter and number.
RUN useradd -m -d /home/docker  docker
#TODO password is docker, change it
RUN echo 'docker:docker' | chpasswd
RUN sed -Ei 's/adm:x:4:/docker:x:4:docker/' /etc/group
RUN adduser docker sudo

# Set the default shell as bash for docker user.
RUN chsh -s /bin/bash docker

RUN echo 'export WINEDLLOVERRIDES="msvcr110,msvcp110=n,b"' >> /home/docker/.bashrc
RUN echo '#!/bin/bash \n x11vnc -auth /home/someuser/.Xauthority -display :10 -create -forever &' >> /home/docker/startvnc.sh
RUN chown docker:docker /home/docker/startvnc.sh
RUN chmod +x /home/docker/startvnc.sh

RUN echo '#!/bin/bash \n jwm & \n xterm &' >> /home/docker/.xsession
RUN chmod +x /home/docker/.xsession
RUN chown docker:docker /home/docker/.xsession

RUN echo '#!/bin/bash \n cd /home/docker/.wine/drive_c/Program\ Files*86*/rFactor2/Launcher \n wine Launch\ rFactor.exe' >> /home/docker/runrf2.sh
RUN chmod +x /home/docker/runrf2.sh
RUN chown docker:docker /home/docker/runrf2.sh



# Start xdm and ssh services.
CMD ["/bin/bash", "/src/startup.sh"]

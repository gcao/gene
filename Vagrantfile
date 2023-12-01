# -*- mode: ruby -*-
# vi: set ft=ruby :

APP_DIR = "/vagrant"

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://atlas.hashicorp.com/search.
  config.vm.box = "bento/ubuntu-18.04"

  config.ssh.forward_x11 = true

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  config.vm.provider "virtualbox" do |vb|
    vb.name = "gene2"

    # Forward GDB port
    # config.vm.network "forwarded_port", guest: 1234, host: 1234

    # Customize the amount of memory on the VM:
    vb.memory = "3072"
    # vb.gui = true
  end

  config.vm.network "private_network", type: "dhcp"

  # Install rust osdev toolkit and some standard utilities
  # these run as user vagrant instead of root
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    sudo apt-get update
    sudo apt-get upgrade
    sudo apt-get autoremove
    sudo apt-get install build-essential
    sudo apt-get install gdb
    sudo apt-get install llvm lldb
    sudo apt-get install python3 python3-dev python3-pip -y
    sudo apt-get install vim git nasm -y
    #sudo apt-get install xorriso -y
    sudo apt-get install texinfo flex bison python-dev ncurses-dev -y
    sudo apt-get install cmake libssl-dev -y

    # Install linux-tools which contains perf
    sudo apt-get install linux-tools-4.15.0-51-generic

    sudo apt-get install valgrind -y
    sudo apt-get install xfce4 virtualbox-guest-dkms virtualbox-guest-utils virtualbox-guest-x11 -y
    sudo apt-get install kcachegrind -y

    sudo python3 -m pip install --upgrade pip
    sudo python3 -m pip install requests

    curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y

    mkdir -p $HOME/.nimble/tools
    curl https://raw.githubusercontent.com/nim-lang/Nim/devel/bin/nim-gdb --output $HOME/.nimble/tools/nim-gdb
    curl https://raw.githubusercontent.com/nim-lang/Nim/devel/tools/nim-gdb.py --output $HOME/.nimble/tools/nim-gdb.py
    chmod a+x $HOME/.nimble/tools/nim-gdb

    echo 'export PATH="$HOME/bin:$HOME/.nimble/bin:$HOME/.nimble/tools:$PATH"' >> $HOME/.bashrc
    echo "cd #{APP_DIR}" >> $HOME/.bashrc
  SHELL

  # config.vm.synced_folder "", APP_DIR, type: "nfs"
  # If above does not work, run this command:
  # sudo mount 172.28.128.1:/System/Volumes/Data/Users/gcao/proj/gene /vagrant
end

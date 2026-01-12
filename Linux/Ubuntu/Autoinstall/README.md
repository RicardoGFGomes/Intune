  ## 🎯 Overview

  Ubuntu Autoinstall is a feature that allows for automatic, unattended installation of Ubuntu operating systems. This process is supported in Ubuntu Server versions 20.04 and later, as well as Ubuntu Desktop versions 23.04 and later1. The autoinstall format uses YAML configuration files to predefine installation settings, enabling the installation to proceed without user interaction. This '**autoinstall.yaml**' file was created to provide a quick an easy way to deploy a Linux machine with Ubuntu 24.04 LTS or later and test Intune's Linux Management capabilities.
  
  ## 🚀 Getting Started
   
  ### Prerequisites
  
  Ensure you have the following:
  
  - Test device, virtual (prefered) or physical with direct internet access
  - Ubuntu Desktop 24.04 LTS or later ISO
  - A location to store your modified 'autoinstall.yaml' (example: Github or Webserver)
  
  ## 📘Autoinstall YAML explation
  
  The following sections describes how and why some sections are configured the way they are. <br>
  

## **autoinstall** <br>
**Intro**: 'autoinstall' is the global key on the configuration file that marks the beginning of the autoinstall schema and configuration.<br>
**Description**: It's important that we start our configurations as per the example below, as it's part of the schema and it can be properly interpreted by Subiqituy installer framework. he following lines, called 'top-level keys,' will instruct the installer on how to configure specific components in the operating system, such as disk layout, packages to install just to name a few. <br>
```yaml
#cloud-config
autoinstall:
   version: 1
```
**Reference**: [Autoinstall Documentation](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)

## **updates**
**Intro**: Changes the default behavior of updating the system after the installation. <br>
**Description**: By default autoinstall will only search and install for security updates, modifying to all, it will will search and install Security and Package updates<br>

```yaml
updates: all
```
**Reference**: [Autoinstall Documentation - Updates](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=%22Europe/London%22-,updates)

## **shutdown**
**Intro**: Changes the default behavior of rebooting the device when the unattended installation end's. <br>
**Description**: Shutting down the device allows the removal of the installation media and avoiding the device to boot again into the Live CD. <br>
 
```yaml
shutdown: poweroff
```
**Reference**: [Autoinstall Documentation - Shutdown](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=updates%3A%20all-,shutdown)

## **source**
**Intro**: <br>
**Description**: <br>
```yaml
source:
id: ubuntu-desktop-minimal
```
**Reference**: [Autoinstall Documentation - Source](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=toggle%3A%20alt_shift_toggle-,source)

## **user-data** <br>
**Intro**: <br>
**Description**: <br>
```yaml
user-data:
   users: [""]
   disable_root: true
```
**Reference**: [Autoinstall Documentation - user-data](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#ai-user-data)

## **apt**
**Intro**: While it's possible to configure the sources list in the 'late-commands' section as we would normaly do on a terminal, configuring the lists in this section will simplify adding external repositories to the installer and target system.<br>
**Description**: To configure an external repository, we will require the following information:
* Name for the source list file
* The URL of the external repository in the format of an APT Repository Entry (example: "deb http://url codename section")<br>
* Fingerprint of the GPG key that is signing the repository and it's used by APT to verify the authenticity of the packages<br>

The first two are straight foward, the filename will be taken from the sub-key of sources (in the example below 'microsoft-prod.list' and 'microsoft-edge-stable.list'), next the 'source' will be the package manager APT Repository Entry and finally the 'keyid' is the fingerprint of the GPG key of the repository.<br>
<br>
To get the keyid, first download the gpg key from the repository and import it using with gpg command:<br>

```bash
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
gpg --import microsoft.gpg
```
Once the key is imported, use gpg again with the `--list-keys` paramenter to list the imported keys. The output should be something similar to this:
```bash
gpg --list-keys
/home/username/.gnupg/pubring.kbx
--------------------------------
   pub   rsa2048 2015-10-28 [SC]
         BC528686B50D79E339D3721CEB3E94ADBE1229CF
   uid           [ unknown] Microsoft (Release signing) <gpgsecurity@microsoft.com>
```
From the output above, copy the 40 character line below the relevant public GPG key. Run the gpg command one last time with the parameter `--fingerprint` followed by the fingerprint copied earlier:
```bash
gpg --fingerprint BC528686B50D79E339D3721CEB3E94ADBE1229CF
   pub   rsa2048 2015-10-28 [SC]
         BC52 8686 B50D 79E3 39D3  721C EB3E 94AD BE12 29CF
   uid           [ unknown] Microsoft (Release signing) <gpgsecurity@microsoft.com>
```
On the example above, the string **'8686 B50D 79E3 39D3  721C EB3E 94AD BE12 29CF'** is the value we need for the 'keyid' for the Microsoft repository. <br>

```yaml
apt:
   sources:
      microsoft-prod.list:
         source: "deb https://packages.microsoft.com/ubuntu/24.04/prod noble main"
         keyid: BC52 8686 B50D 79E3 39D3  721C EB3E 94AD BE12 29CF
      microsoft-edge-stable.list:
         source: "deb https://packages.microsoft.com/repos/edge stable main"
         keyid: BC52 8686 B50D 79E3 39D3  721C EB3E 94AD BE12 29CF
```
**Reference**: [Autoinstall Documentation - apt](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=http%3A//172.16.90.1%3A3128-,apt)

## **storage** <br>
**Intro**: Create's an LVM partition and Encrypts it with "ubuntu" as default the password<br>
**Description**: In this example the goal is to create an LVM and encrypt it using LUKS so we can test the Intune device compliance policies. It's possible to use this section to create a more complex disk partitions layout and more informatiom about this can be found in the reference link below.<br>

```yaml
storage:
   layout:
      name: lvm
      password: ubuntu
```
**Reference**: [Autoinstall Documentation - storage](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=geoip%3A%20false-,storage)

## **packages** <br>
**Intro**: Specifies additional packages that will be installed during the provisioning of the target system<br>
**Description**: Add here any extra packages required for your VM. Make sure to add the correct sources under the APT section if the package if is not on the default Ubuntu's repository (example: microsoft-edge-stable and intune-portal)<br>

```yaml
packages:
   - curl
   - wget
   - gpg
   - software-properties-common
   - apt-transport-https 
   - ca-certificates
   - libpam-pwquality
   - microsoft-edge-stable 
   - intune-portal
```
**Reference**: [Autoinstall Documentation - packages](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=enable%20boolean%20true-,packages)

## **snaps** <br>
**Intro**: A list of self-contained applications to install using snaps package manager<br>
**Description**: This section is optional, allow's you to install extra applications from the snaps manager<br>

```yaml
snaps:
   - name: code
      classic: true
   - name: powershell
      classic: true
```
**Reference**: [Autoinstall Documentation - snaps](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=install%3A%20false-,snaps)

## **late-commands** <br>
**Intro**: The commands below will be executed after the target system installation is complete and before the reboot or shutdown of the system<br>
**Description**: In this Autoinstall YAML file, we will perform any extra configurations to minimize any manual configuration once we reach the desktop and before enrolling our test device into Intune: <br><br>
Enforces that users password's needs to meet certain criteria when created or updated. This option is **required** if you plan on enforcing or testing the password quality in Intune's compliance check. The example below enforces that the password contains at least one numeric, one alphanumeric lower case, one alphanumeric uper case, one special character and it should be at least 12 characters long. [More information on how to configure the pam_pwquality module](https://manpages.ubuntu.com/manpages/noble/man8/pam_pwquality.8.html).

```yaml
- curtin in-target --target=/target -- sh -c 'sed -i -e "s/pam_pwquality.so retry=3/pam_pwquality.so retry=3 dcredit=-1 ocredit=-1 ucredit=-1 lcredit=-1 minlen=12/g" /etc/pam.d/common-password'
```
Customizing GNOME desktop environment by adding Microsoft (Microsoft Edge, Company Portal, etc..) and a few Linux  Apps (Terminal, Files, etc..) to the [Gnome Dock](https://help.gnome.org/admin/system-admin-guide/stable/desktop-favorite-applications.html.en).<br>
These next lines are **optional**.
```yaml
- | 
   cat << EOF > /target/etc/dconf/profile/user
   user-db:user
   system-db:local
   EOF
- curtin in-target --target=/target -- sh -c 'mkdir -p /etc/dconf/db/local.d/'
- | 
   cat << EOF > /target/etc/dconf/db/local.d/00-favorite-apps 
   [org/gnome/shell]
   favorite-apps = ['microsoft-edge.desktop', 'intune-portal.desktop', 'code_code.desktop', 'snap-store_snap-store.desktop', 'org.gnome.Terminal.desktop', 'powershell_powershell.desktop', 'org.gnome.Nautilus.desktop']
   EOF
- curtin in-target --target=/target -- sh -c 'dconf update'
```
Check's if the APT Repository List file `microsoft-edge.list` file exists and if it does removes it. During the testing of this autoinstall yaml file, the unattended installation failed due to APT returning a code 2. Uppon reading the logs, this error was pointing to a duplicated sources list entry; one of the files was generated by the entry on the autoinstall yaml file on the apt section (`microsoft-edge-stable.list`) and another one was automatically generated (`microsoft-edge.list`). I 'm not sure what is generating this file but is causing autoinstall to not complete sucessefully, i would recommend keeping these lines to avoid any provisioning failures. This next line is **optional**.
```yaml
- curtin in-target --target=/target -- sh -c 'if [ -e /etc/apt/sources.list.d/microsoft-edge.list ]; then rm -f /etc/apt/sources.list.d/microsoft-edge.list; fi'
```
Making sure that the system is up-to-date and performing cleanup
```yaml
- curtin in-target --target=/target -- apt update && apt dist-upgrade -y
- curtin in-target --target=/target -- apt autoremove -y
- curtin in-target --target=/target -- apt autoclean
```

**Reference**: [Autoinstall Documentation - late-commands](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html#:~:text=shutdown%3A%20poweroff-,late%2Dcommands)

## ⚠️ Disclaimer

This yaml configuration is provided **as-is** without any warranty or support. The author assumes no responsibility for any issues, damages, or unintended consequences arising from the use of this file. Use it at your own risk.

This project is offered to the public for educational and testing purposes. No official support, maintenance, or updates are guaranteed. By using this file, you acknowledge and accept these terms.
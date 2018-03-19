Nolij Website Backup Script Readme
==================================

The Nolij Website Backup script was created to act as a generic
backup script for all of Nolij's website projects. This script
creates compressed tar archives of website directories and uploads
those directories to AWS S3 buckets.

Additionally, the script can be invoked to backup associated MySQL
databases and to send notification emails.

Configuring Dependencies:
-------------------------

### Configuring AWS CLI

This script relies on the AWS CLI utility to upload packages to S3
buckets. This commandline utility can be installed using `apt
install awscli`. Once installed you will need to configure it by
creating an AWS IAM role and generating sign in credentials keys.
When you generate these keys AWS will prompt you to download the
private key as a PEM file. At Nolij, we use the following key:
http://wiki.elucidsolutions.com/index.php/Elucid_Website_Server:_GSA_S3_Account.

To configure AWS CLI to use a key pair, create the
~/.aws/credentials file and add the following lines (substituting
the key ID and secret key with their correct values).

```
[default]
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### Configuring SSH

This script uses SSH and SCP to connect to remote servers. To run,
SSH must be configured so that it can connect to the given servers
without prompting for a password. To do this you should add an entry
to the ~/.ssh/config file for each server that you plan to backup
using this script. For example, given a remote server at 52.4.197.127
you can configure SSH to connect as "ubuntu" without a password by
adding something like the following to ~/.ssh/config:

```
Host 52.4.197.127
User ubuntu
Port 22
IdentityFile ~/.ssh/elucid_website_server.pem
```

### Configuring MySQL

This script calls `mysqldump` to create database backups. To use
this program, MySQL must be configured to allow users to log in
without prompting for a password. Use `mysql_config_editor` to do
this. For example run:

```
> mysql_config_editor set --login-path="client" --host="localhost" \
    --user="USER" --password
```

Warning: When you enter your password enclose it in double quotes.

to associate a default password with the user "USER".

### Configuring Mutt

Finally, we rely on Mutt to send notification emails. To use Mutt,
you must configure it locally to connect to the mail server that
you'd like to send emails over. To configure Mutt, edit the ~/.muttrc
file. For example, my ~/.muttrc file contains the following:

```
set my_pass = "xxxxxxxxxxx"
set my_user = "larry.lee@nolijconsulting.com"
set realname = "Larry Lee"
set from = "larry.lee@nolijconsulting.com"
set smtp_url = smtp://$my_user:$my_pass@smtp-mail.outlook.com:587
set ssl_force_tls = yes
set ssl_starttls = yes
```

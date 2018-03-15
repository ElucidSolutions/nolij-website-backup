# The following script logs into a remote server,
# creates a tar archive of a website directory,
# creates a MySQL dump of a given MySQL database,
# generates SHA1 hashes for both backups, and
# posts the backups to an S3 instance.

# Set the default parameter values.
verbose=0
database=""
user=""
host=""
path=""
bucket=""
log=""
backups=$(mktemp -d)
to=""
cc=""
name=""

# Accepts one argument: msg, a log message string
# and appends the string to the message log along
# with a timestamp.
function log () {
  local msg="$1"
  if [[ ! -z $log ]]
  then
    local prefix="[$(date)] "
    echo "${prefix}${msg}" >> $log
  fi
}

# Accepts one argument: msg, a notification
# message string; and prints the given message if
# the verbose flag has been set.
function notice () {
  local msg="$1"
  if [[ $verbose == 1 ]]
  then
    echo -e "\033[44mNotice:\033[0m $msg"
    log "Notice: $msg"
  fi
}

# Accepts one argument: msg, an email message
# body string; and sends msg over email to the
# given email recipients.
function email () {
  local msg="$1"
  if [[ ! -z $to ]]
  then
    notice "Sending notification email..."
    mutt -s "$name Backup Notification" $to $cc <<< $msg
    notice "Sent notification email."
  fi
}

# Accepts one argument: emsg, an error message
# string; and prints the given error message.
function error () {
  local emsg=$1
  (>&2 echo -e "\033[41mError:\033[0m $emsg")
  log "Error: $emsg"
  rm -rf $backups
  email "An error occured while trying to backup $name."
  exit 1
}

log "Notice: Generating backup."

options=$(getopt --options="hvl:d:e:c:n:u:h:p:b:" --longoptions="help,verbose,log:,database:,email:,cc:,name:,version,user:,host:,path:,bucket:" -- "$@")
[ $? == 0 ] || error "The command line includes one or more unrecognized arguments."

eval set -- "$options"
while true
do
  case "$1" in
   -h| --help)
    cat <<- EOF
Usage: backup.sh [options] <parameters>

This script creates website backups. The script is designed to
backup websites that consist of a collection of files stored within
a web directory and a MySQL database hosted on the same server. When
run, this program uses tar to backup the directory containing the
website's source files and uses mysqldump to backup the associated
website. It then transfers these to an Amazon Web Services (AWS)
Simple Storage Service (S3) bucket.

Options:

  -h|--help
  Displays this message.

  -v|--verbose
  Enables verbose output.

  -l|--log <log file path>
  The path of the log file that log events and notifications should
  be written to.

  -d|--database <database name>
  The name of the web site's MySQL database. This script assumes the
  database is hosted on the sever referenced by --host. If omitted,
  this script will not attempt to backup the database.

  Note: we recommend that you use mysql_config_editor to configure
  mysqldump so that you can log into mysql without a password on
  the website server.

  -e|--email <email address>
  If given, this parameter instructs this script to send a
  notification emails to the given address.

  -c|--cc <email addresses>
  This parameter gives a space delimited list of email addresses
  that should be carbon copied on any notification emails.

  --version
  Displays this program's version number.

Required Parameters:

  -n|--name <website name>
  The name of the website being backed up. This name is used in
  the notification emails.

  -u|--user <user name>
  The name of the user that this script will attempt to log into
  the web server under.

  -h|--host <URL>
  The web server URL.

  -p|--path <remote path>
  The path of the directory containing the web site's source files
  on the web server.

  -b|--bucket <bucket URI>
  The AWS S3 bucket that this script will store backups on.

Examples:

  ./backup --user="ubuntu" --host="31.12.88.2" --path="/example" --bucket="bucket"
  This command will log into 31.12.88.2 as the user named ubuntu,
  use tar to backup the /example directory, and store the backup
  files in s3://bucket.

Dependencies:

  aws-cli
  This script uses the AWS command line interface utility (aws-cli)
  to upload backups to S3 buckets.

  mutt
  This script uses mutt to send notification emails.

Authors:

  Larry D. Lee jr. <llee454@gmail.com>
EOF
      exit 0;;
    --version)
      echo "1.0.1"
      exit 0;;
    -v|--verbose)
      verbose=1
      shift ;;
    -l|--log)
      log=$2
      shift 2;;
    -n|--name)
      name=$2
      shift 2;;
    -d|--database)
      database=$2
      shift 2;;
    -e|--email)
      to=$2
      shift 2;;
    -c|--cc)
      read -a recipients <<< $2
      for recipient in "${recipients[@]}"
      do
        cc="$cc -c $recipient"
      done
      shift 2;;
    -u|--user)
      user=$2
      shift 2;;
    -h|--host)
      host=$2
      shift 2;;
    -p|--path)
      path=$2
      shift 2;;
    -b|--bucket)
      bucket="s3://$2"
      shift 2;;
    --)
      shift
      break;;
  esac
done

[[ -z $name ]]   && error "The --name command line parameter is missing."
[[ -z $user ]]   && error "The --user command line parameter is missing."
[[ -z $host ]]   && error "The --host command line parameter is missing."
[[ -z $path ]]   && error "The --path command line parameter is missing."
[[ -z $bucket ]] && error "The --bucket command line parameter is missing."

notice "Connecting to $host as $user and storing a backup of $name (at $path) in $bucket..."

# Accepts one argument: cmd, a command string;
# and executes the given command on the remote
# server.
function execute () {
  local remote_cmd="$1"
  local cmd="ssh $user@$host '$remote_cmd'"
  notice "$cmd"
  eval "$cmd"
  [ $? == 0 ] || error "An error occured while trying to execute "'"'"$remote_cmd"'"'" on "'"'"$host"'"'"."
}

# Accepts one argument: path, a file path;
# and copies the referenced file into the backups
# directory.
function retrieve () {
  local path="$1"
  local cmd="scp $user@$host:$path $backups"
  notice "$cmd"
  eval "$cmd"
  [ $? == 0 ] || error "An error occured while trying to download "'"'"$path"'"'" from "'"'"$host"'"'"."
}

# Accepts one argument: path, a local file path;
# and generates an SHA1 hash for the referenced
# file.
function hash () {
  local path="$1"
  local cmd="sha1sum $path > $path.sha1"
  notice "$cmd"
  eval "$cmd"
  [ $? == 0 ] || error "An error occured while trying to hash "'"'"$path"'"'"."
}

# Accepts one argument: path, a local file path;
# and uploads the given file to the AWS bucket.
function upload () {
  local path="$1"
  local cmd="aws s3 cp $path $bucket"
  notice "$cmd"
  eval "$cmd"
  [ $? == 0 ] || error "An error occured while trying to upload "'"'"$path"'"'" to "'"'"$bucket"'"'"."
}

# I. Backup the web directory.

datestamp=$(date +%m%d%y)
directory_backup_basename="$(basename $path)-$datestamp"
directory_backup_name="$directory_backup_basename.tar.bz2"
directory_backup_path="$backups/$directory_backup_name"
directory_backup_hash_path="$directory_backup_path.sha1"

notice "Backing up the web directory..."
execute "tar --bzip2 -cf $directory_backup_name $path"
notice "Backed up the web directory."

notice "Downloading the web directory backup..."
retrieve $directory_backup_name
notice "Downloaded the web directory backup."

notice "Cleaning up the remote web directory backup..."
execute "rm -rf $directory_backup_name"
notice "Cleaned up the remote web directory backup."

notice "Hashing the web directory backup..."
hash $directory_backup_path
notice "Hashed the web directory backup."

notice "Uploading the web directory backup to AWS..."
upload $directory_backup_path
upload $directory_backup_hash_path
notice "Uploaded the web directory backup to AWS."

if [[ ! -z $database ]]
then
  database_backup_name="$database-$datestamp.sql"
  database_backup_path="$backups/$database_backup_name"
  database_backup_hash_path="$database_backup_path.sha1"

  notice "Backing up the database..."
  execute "mysqldump $database" > $database_backup_path
  notice "Backuped up the database."

  notice "Hashing the database backup..."
  hash $database_backup_path
  notice "Hashed the database backup."

  notice "Uploading the database backup..."
  upload $database_backup_path
  upload $database_backup_hash_path
  notice "Uploaded the database backup."
fi

notice "Cleaning up local files..."
rm -rf $backups
notice "Cleaned up local files."
email "Successfully Backed up $name on $host."
notice "Done."
exit 0

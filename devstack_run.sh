#!/bin/bash

. ./config

DEVSTACK_BRANCH="master"
LOG=./logs
SUMMARY=$LOG/summary
LOGFILE=$LOG/log
LOCALRC="localrc"
LOCALCONF=""
SUDO="sudo -S"
APTGETUPDATE="$SUDO apt-get update"
APTGETINSTALL="$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y"
APTGETREMOVE="$SUDO apt-get remove -y"

DEVSTACK_REPO=https://github.com/openstack-dev/devstack.git

SSH_KEY="id_rsa"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSHCMD="$SSH -i $SSH_KEY -t -l ubuntu"
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCPCMD="$SCP -i $SSH_KEY"

#usa_vone="6192292c-1249-4b5b-aeb7-9a0637850d4b"
#usa_vtwo="baa050fe-12fe-4b55-b2c5-b3df3c03e871"
#usa_vfour="fa6ca004-ca90-47a4-bd5c-9c9570bf36cb"
#usa_veight="2573b3c3-6e8f-4377-8ff2-26d6030ddc88"
vtwo="0b41ab6e-696e-4a91-b623-5b880e3be7a6"
vfour="3164027a-3636-4cd5-a8be-f76d51d93a1a"
veight="a40f2dba-e51d-4175-a41d-8c0047e589b7"
SERVICEOFFERINGID=$vfour
#TEMPLATEID=""
ZONEID="1b02e74c-6c21-4aa3-b96c-51042de8fccd"
#usa_ZONEID="d308161c-0311-4c60-9828-e671847f6f21"

function echo_summary() {
    echo "$@" >&6
}

function title() {
    prefix=${1:-"**"}
    echo_summary "$prefix $TITLE"
}

function result() {
    msg=$1
    rc=$2
    prefix=${3:-"***"}
    
    if [ $rc -eq 0 ]; then
        test -n "$msg" && echo_summary "$prefix $TITLE: $msg: success"
        test -n "$msg" || echo_summary "$prefix $TITLE: success"
    else
        test -n "$msg" && echo_summary "$prefix $TITLE: $msg: failed"
        test -n "$msg" || echo_summary "$prefix $TITLE: failed"
        die_error
    fi
}

function pause() {
    msg=$1
    
    test $DEBUG != "True" && return
    if [ -z "$msg" ]; then
        echo_summary "Enter key to continue"
    else
        echo_summary "Enter key to $msg"
    fi
    read
}

dying=0
function die() {
    rc=$1
    test $dying -ne 0 && return
    dying=1
    
    terminate_vm
    exit $rc
}

function die_intr() {
    echo_summary "Aborting by user interrupt"
    trap "" SIGINT
    die 1
}
function die_error() {
    trap "" SIGINT
    die 1
}

function run_vm() {
    
    TITLE="start virtual machine: vm"
    title "++"

    VM_ID=`./kick_api.sh command=deployVirtualMachine serviceofferingid=$SERVICEOFFERINGID templateid=$TEMPLATEID zoneid=$ZONEID | python -c "import sys, fileinput; from xml.etree.ElementTree import *; elem=fromstring([line for line in fileinput.input()][0]); sys.stdout.write(elem.findtext('id'));"`
    result "" $? "++"
    
    TITLE="wait for virtual machine to come up: vm"
    title "++"
    fail=1
    for (( i=0; i<36; i++ )); do
	VM_IP=`./kick_api.sh command=listVirtualMachines | python -c "import sys, fileinput; from xml.etree.ElementTree import *; elem=fromstring([line for line in fileinput.input()][0]); [sys.stdout.write(item.find('nic').findtext('ipaddress')) for item in elem.getiterator('virtualmachine') if item.findtext('id') == '$VM_ID'];"`
        $SSHCMD $VM_IP true
        if [ $? -eq 0 ]; then
            fail=0
            break
        fi
        sleep 30
    done
    result "" $fail "++"
}

function terminate_vm() {
	./kick_api.sh command=destroyVirtualMachine id=$VM_ID
}

function install_pkgs() {
    ipaddr=$1
    vmname=$2

    TITLE="install packages: $vmname"
    title "++"

    cat <<EOF | $SSHCMD $ipaddr
set -x
$APTGETUPDATE > /dev/null
$APTGETINSTALL git
$SUDO sh -c "echo '127.0.0.1       localhost ubuntu' > /etc/hosts"
$SUDO sh -c "echo '127.0.1.1       ubuntu' >> /etc/hosts"
EOF

    result "" $? "++"
}

function start_devstack() {
    ipaddr=$1
    vmname=$2
    
    TITLE="install devstack: $vmname/$ipaddr"
    title "++"

    cat <<EOF | $SSHCMD $ipaddr
set -x
git clone $DEVSTACK_REPO -b $DEVSTACK_BRANCH
EOF
    $SCPCMD $LOCALRC ubuntu@$ipaddr:devstack/localrc
    result "" $? "++"
        
    TITLE="start devstack: $vmname/$ipaddr"
    title "++"

    $SSHCMD $ipaddr VERBOSE=True devstack/stack.sh &
    pid=$!
    fail=1
    for (( i=0; i<30; i++ )); do
        kill -0 $pid 2>/dev/null
        if [ $? -ne 0 ]; then
            fail=0
            break
        fi
        sleep 60
    done
    msg=""
    if [ $fail -ne 0 ]; then
        $SUDO kill -9 $pid
        msg="timeout"
    fi
    wait $pid
    result "$msg" $? "++"
}

rm -rf $LOG
mkdir -p $LOG

# setup output redirection
exec 3>&1
if [ "$VERBOSE" = "True" ]; then
    exec 1> >( tee "$LOGFILE" ) 2>&1
    exec 6> >( tee "$SUMMARY" )
else
    exec 1> "$LOGFILE" 2>&1
    exec 6> >( tee "$SUMMARY" /dev/fd/3 ) 
fi

trap die_intr SIGINT

echo_summary "++ preparing virtual machine"
run_vm

install_pkgs $VM_IP vm

start_devstack $VM_IP vm

echo_summary "++ VM ID = $VM_ID"
echo_summary "++ VM IP = $VM_IP"

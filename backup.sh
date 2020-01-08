#!/bin/bash

## Variables
DTE=$(date --utc +%FT%T.%3NZ)
TYPE=production

## Functions
get_prod_instance_ids(){
    printf "Getting all ${TYPE} instances...\n"
    INSTANCES=$(aws ec2 describe-instances --filters Name=tag:type,Values=${TYPE} | egrep -o '"i-[0-9a-z]{17}"' | sed 's/"//g')
}

get_snapshot_ids(){
    printf "Getting all ${TYPE} snapshots older than 1 day...\n"
    SNAPSHOTS=$(aws ec2 describe-snapshots --owner self | jq '.Snapshots[] | select(.StartTime < "'$(date --utc +%FT%T.%3NZ --date='-1 day')'") | [.Description, .StartTime, .SnapshotId]' | egrep -o "snap-[0-9a-z]{17}")
}

delete_snapshot(){
    printf "Deleting snapshot ${SNAPSHOT_ID}...\n"
    aws ec2 delete-snapshot --snapshot-id ${SNAPSHOT_ID}
}

get_volume_id(){
    printf "Getting volume ID from instance ${INSTANCE_ID}...\n"
    VOLUME_ID=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | egrep -o "vol-[0-9a-z]{17}")
}

get_instance_state(){
    #printf "Getting state for instance ${INSTANCE_ID}...\n"
    STATE=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq '.Reservations[].Instances[].State.Name' | sed 's/"//g')
}

shutdown_instance(){
    printf "Shutting down instance ${INSTANCE_ID}...\n"
    aws ec2 stop-instances --instance-ids ${INSTANCE_ID} > /dev/null
    get_instance_state
    until [ ${STATE} == "stopped" ]; do
        printf "Waiting for instance to stop, please wait...\n"
        sleep 5
        get_instance_state
    done
}

start_instance(){
    printf "Starting instance ${INSTANCE_ID}...\n"
    aws ec2 start-instances --instance-ids ${INSTANCE_ID} > /dev/null
}

create_snapshot(){
    printf "Creating snapshot for instance ${INSTANCE_ID}...\n"
    SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id ${VOLUME_ID} --description "Backup of instance ${INSTANCE_ID}" | egrep -o "snap-[0-9a-z]{17}")
    get_snapshot_state
    until [ ${STATE} == "completed" ]; do
        printf "Waiting for snapshot to complete, please wait...\n"
        sleep 5
        get_snapshot_state
    done
}

get_snapshot_state(){
    #printf "Getting state for snapshot ${SNAPSHOT_ID}...\n"
    STATE=$(aws ec2 describe-snapshots --snapshot-ids ${SNAPSHOT_ID} | jq '.Snapshots[].State' | sed 's/"//g')
}

execute_backup(){
    get_prod_instance_ids
    for INSTANCE_ID in ${INSTANCES}; do
        get_volume_id
        shutdown_instance
        create_snapshot
        start_instance
    done
}

execute_cleanup(){
    get_snapshot_ids
    for SNAPSHOT_ID in ${SNAPSHOTS}; do
        delete_snapshot
    done
}

## Execute

#execute_backup
execute_cleanup

# AsrReplication

This are a script to migrate big amounts of machines using ASR on Azure and CSV file.

1 - asr_migration.ps1 (enable the sync to Azure).

2 - asr_updateproperties.ps1 (Update the propierties on the replication).

3 - asr_properties_check.ps1	(Check if the properties are ok comparing the properties on the CSV).

4 - asr_test_failover.ps1 (Test the failover)

5 - asr_cleanup_failover.ps1 (Clean the fail over on ASR)
Now it is time to stop the machine. (not mandatory)
6 - asr_failover.ps1 (Make the failover to Azure)

7 - asr_complete.ps1 (Complete the migration deleting all in ASR).

asr_migration_status.ps1	 What is the status of the sync

Assing one NSG to one nic. asr_post_failover.ps1

The CSV must have this values per line. This header must be on the first line of the file, one line per machine.

VAULT_SUBSCRIPTION_ID,VAULT_NAME,SOURCE_MACHINE_NAME,TARGET_MACHINE_NAME,CONFIGURATION_SERVER,PROCESS_SERVER,TARGET_RESOURCE_GROUP,TARGET_STORAGE_ACCOUNT,TARGET_STORAGE_ACCOUNT_RG,TARGET_VNET,TARGET_VNET_RG,TARGET_SUBNET,REPLICATION_POLICY,ACCOUNT_NAME,AVAILABILITY_SET,PRIVATE_IP,MACHINE_SIZE,TESTFAILOVER_RESOURCE_GROUP,TESTFAILOVER_VNET

This is all.

# AsrReplication

These are a set of scripts to migrate big amounts of machines using Azure Site Recovery (ASR) in VMWare mode (see https://docs.microsoft.com/en-us/azure/site-recovery/vmware-azure-disaster-recovery-powershell for further information)
The scripts will use an input CSV file where each row must contain the data for each machine you want to migrate
Below a typical execution order in order to do the migration:
- 1 - asr_migration.ps1 (Enable the sync to Azure).
- 2 - asr_updateproperties.ps1 (Update some additional properties on the replication information that it is not possible to set when the sync is created).
- 3 - asr_properties_check.ps1 (Check if the properties are ok compared to the properties on the CSV).
- 4 - asr_test_failover.ps1 (Test the failover)
- 5 - asr_cleanup_failover.ps1 (Clean the fail over on ASR)

Now it is time to stop the machine. (It is not mandatory but it is recommended)
- 6 - asr_failover.ps1 (Make the failover to Azure)
- 7 - asr_complete.ps1 (Complete the migration deleting resources in ASR).

Additional scripts:
- Check sync status:
  - asr_migration_status.ps1 (Check sync status)

- Assign one NSG to one nic after failver:
    - asr_post_failover.ps1

Input CSV must be created with a header line with these values:

`VAULT_SUBSCRIPTION_ID,VAULT_NAME,SOURCE_MACHINE_NAME,TARGET_MACHINE_NAME,CONFIGURATION_SERVER,PROCESS_SERVER,TARGET_RESOURCE_GROUP,TARGET_STORAGE_ACCOUNT,TARGET_STORAGE_ACCOUNT_RG,TARGET_VNET,TARGET_VNET_RG,TARGET_SUBNET,REPLICATION_POLICY,ACCOUNT_NAME,AVAILABILITY_SET,PRIVATE_IP,MACHINE_SIZE,TESTFAILOVER_RESOURCE_GROUP,TESTFAILOVER_VNET,TARGET_NSG_NAME,TARGET_NSG_RESOURCE_GROUP`

After header, each row must provide migration values according to these header fields for each machine to be migrated  
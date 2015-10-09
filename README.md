# esxi_backupper
backups on esx server with ssh access

/bin/kill $(cat /var/run/crond.pid)                                      
/bin/echo '0 3 * * * /suuhm/bak.sh >> /var/spool/cron/crontabs/root    
/bin/crond                                                               
                                                                         
                                                                         
You will need to change                                                  
1. The NFS definitions at the top of this script.                        
2. The "Cycle" definition underneath it if you don't want a rotating 0-4 
   backup daily structure.                                               
3. The code labelled "README" around line 270, which chooses which       
   datastores to backup.                                                 
                                                                         
For command-line usage, run the command with the "--help" option as the  
only argument on the command-line.                                       

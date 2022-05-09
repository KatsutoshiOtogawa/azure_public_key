# github action + ssh + azure

## 


[git hub action](https://github.com/Burnett01/rsync-deployments)

 az sshkey create `
         --name aaa_key `
         --resource-group resource_east


        az vm create `
            --name aaa `
            --resource-group resource_east `
            --image "RedHat:RHEL:7-LVM:latest" `
            --storage-sku Standard_LRS `
            --custom-data cloud-init.txt `
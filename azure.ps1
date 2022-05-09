# azure cliでなくて、msのドキュメント的にもazure powershellがデフォルト担ったら
# azure powershellで書き換える。

# github action用のprincipal作成とgithub actionの
function set_azure_vm_for_github {
    #Requires -Version 7 
    [CmdletBinding()]
    param (
        # UseMaximumSize
        [Parameter(
            Mandatory = $True
            , HelpMessage = "github repository for github action"
        )]
        [String]$repo,

        [Parameter(
            Mandatory = $True
            , HelpMessage = "Creating Azure Virtual Machine Name"
        )]
        [String]$VmName,

        [Parameter(
            Mandatory = $True
            , HelpMessage = "VM Image Name. check 'az vm image list --output table'"
        )]
        [String]$Image,
        [Parameter(
            Mandatory = $False
            , HelpMessage = "VM size. check 'az vm image list --output table'"
        )]
        [String]$Size = "Standard_B1s",
        [Parameter(
            Mandatory = $False
            , HelpMessage = "VM storage SKU. check 'az vm image list --output table'"
        )]
        [String]$StorageSku = "Standard_LRS"
    )
    Set-Variable ErrorActionPreference -Scope local -Value "Stop"

    $DEPLOY_PATH = "/home/app"
    $DEPLOY_PORT = "22"
    $DEPLOY_USER = "github_action"

    # github repositoryが存在するか確認
    try {
        Invoke-WebRequest "https://api.github.com/repos/${repo}" | Out-Null
    } catch {

        $error[0] | Write-Error
    }

    # get azure resouce group name list
    az group list --query "[].{Name:name}" | ConvertFrom-Json | Set-Variable rg_list -Scope local

    # get azure resouce group
    New-Variable rg_group -Scope local
    while ($true) {
        Write-Output $rg_list | Out-String | Out-Host
        read-host "Type you use resource group >" | Set-Variable select_name -Scope local

        # resource groupの存在確認
        if (-not [String]::IsNullOrEmpty($(az group list --query "[?name=='${select_name}'].{Name:name}" --output tsv))){
            $rg_group = (az group list --query "[?name=='${select_name}']" | 
                ConvertFrom-Json)
            break;
        }else {
            Write-Host "Select exists resource group!"
        }
    }

    # github actionのキーをローカルに残さないため、Tempファイルとして作成
    # 厳密にやりたいならexeかjar作って実行させる。
    New-TemporaryFile | Set-Variable key_name -Scope local -Option Constant

    try {
        # ssh keyの作成
        if ($PSVersionTable.Platform -eq "Unix") {
            /bin/sh -c "echo -e 'y\n' | ssh-keygen -q -m PEM -t rsa -b 4096 -f $(key_name.FullName) -N '' "
        } else {

            New-TemporaryFile | Set-Variable tempfile -Scope local -Option Constant
            ($tempfile.FullName -replace "\..*$",".bat") | Set-Variable tempbat_path -Scope local -Option Constant
            Rename-Item $tempfile.FullName -NewName $tempbat_path
        
            Write-Output "gh secret set AZURE_CREDENTIALS --repo $repo < $($principal_json.FullName)" | Set-Content -Path $tempbat_path
            # 下のように必ずWorkingDirectoryを指定すること
            # cmdはディレクトリを跨ぐ処理ができないため。
            Start-Process $tempbat_path -WorkingDirectory (Get-Location | Select-Object -ExpandProperty Path)
            Remove-Item $tempbat_path
            write-output 'y' | ssh-keygen -q -m PEM -t rsa -b 4096 -f $key_name.FullName -N ''
        }

        az vm create `
            --name $VmName `
            --resource-group $rg_group.Name `
            --image $Image `
            --storage-sku $StorageSku `
            --custom-data cloud-init.txt `
            --size $Size `
            --public-ip-sku Standard `
            --tags "test=1" `
            --admin-username $DEPLOY_USER `
            --ssh-key-values "$($key_name.FullName).pub" |
            ConvertFrom-Json |
            Set-Variable vm_info -Scope local -Option Constant
        
        az vm open-port `
            --resource-group $rg_group.Name `
            --name $VmName `
            --port '80,443'

        # 初期はIPaddressを入れておく。
        $DEPLOY_HOST = $vm_info.publicIpAddress

        ##  remote_path: ${{ secrets.DEPLOY_PATH }}
        ##  remote_host: ${{ secrets.DEPLOY_HOST }}
        ##  remote_port: ${{ secrets.DEPLOY_PORT }}
        ##  remote_user: ${{ secrets.DEPLOY_USER }}
        ##  remote_key: ${{ secrets.DEPLOY_KEY }
        if ($PSVersionTable.Platform -eq "Unix") {
            /bin/sh -c "gh secret set DEPLOY_KEY --repo $repo < $($key_name.FullName)"
        } else {

            # cmd実行用のファイルを作成
            New-TemporaryFile | Set-Variable tempfile -Scope local -Option Constant
            ($tempfile.FullName -replace "\..*$",".bat") | Set-Variable tempbat_path -Scope local -Option Constant
            Rename-Item $tempfile.FullName -NewName $tempbat_path

            Write-Output "gh secret set AZURE_CREDENTIALS --repo $repo < $($key_name.FullName)" | Set-Content -Path $tempbat_path
            # 下のように必ずWorkingDirectoryを指定すること
            # cmdはディレクトリを跨ぐ処理ができないため。
            Start-Process $tempbat_path -WorkingDirectory (Get-Location | Select-Object -ExpandProperty Path)
            Remove-Item $tempbat_path
        }
        
        gh secret set DEPLOY_PATH --repo $repo --body $DEPLOY_PATH
        gh secret set DEPLOY_HOST --repo $repo --body $DEPLOY_HOST
        gh secret set DEPLOY_PORT --repo $repo --body $DEPLOY_PORT
        gh secret set DEPLOY_USER --repo $repo --body $DEPLOY_USER
    } finally {
        # 鍵の一時ファイルを確実に削除
        Remove-Item $key_name.FullName
        Remove-Item "$($key_name.FullName).pub"
    }

}

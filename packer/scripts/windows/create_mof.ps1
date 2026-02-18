Import-Module PowerSTIG

Configuration ApplyWindowsServerStig {
    param
    (
        [parameter()]
        [string]
        $NodeName = 'localhost'
    )

    Import-DscResource -ModuleName PowerSTIG

    Node $NodeName {
        WindowsServer 'ConfigureServer' {

            OsVersion = '2022'
            OsRole    = 'MS'
            #StigVersion = '2.1' #automatically choose latest- 2.1 stopped being available as of 3/3/25
            OrgSettings = ".\WindowsServer-2022-MS-2.1.org.pamdata.xml" #no specific org settings provided currently.
            Exception   = @{
                #need to be exceptions to work at all with remote access.
                'V-254439' = @{'Identity'='Guests'} #removed local account from the disallow list: allow local account remote desktop access
                'V-254435' = @{'Identity'='Guests'} #removed local and Admin accounts from the disallow list: allow admin accounts to connect with remote desktop access
                #Exception makes shutdown for users easier which enhances cost savings
                'V-254501' = @{'Identity'='Everyone'} #Allows anyone logged in to be able to shut down. Everyone used instead of Admin and Local because powerstig not properly formatting multiple value response.
                #Password rules are waived as IAP uses GCP credentials (including password) to authenticate, and no other access is permitted by GPC networking.
                'V-254446' = @{'ValueData'='0'} #allow blank password (GCP handles passwords through their auth protocols)
                'V-254289' = @{'PolicyValue'='0'} #allow to permit use of blank password (GCP handles passwords through their auth protocols)
                'V-254290' = @{'PolicyValue'='0'} #disable minimum password age to allow for the pam_admin account password to be cycled on demand which prevents need for storing, memorizing, or managing/versioning this password over different images.
                'V-254291' = @{'PolicyValue'='0'} #allow blank password (GCP handles passwords through their auth protocols).
                'V-254292' = @{'PolicyValue'='Disabled'} #allow blank password (GCP handles passwords through their auth protocols).
            }
            SkipRule = @('V-254254.c') # current bug, issue says to skip it https://github.com/microsoft/PowerStig/issues/1360
        }
    }
}

ApplyWindowsServerStig

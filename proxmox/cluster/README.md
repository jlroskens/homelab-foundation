# Proxmox Cluster Creation and Managment

Tools to creates a proxmox cluster and manage.

## Prerequisites
- Ran the [/dns/technitium/bootstrap/init.sh](/dns/technitium/bootstrap/init.sh) script to configure your host machine.
  - Installs Python + Pip
  - Sets up .bashrc and .profile scripts to read in environment exports under `$HOME/environment_vars/`
- Created more than 1 Proxmox VE Host with the same root user name and password.
- (Optional) Saved the "root" password to an export file under `$HOME/environment_vars/PVE_ROOT_PASSWORD.env`
  - If you don't set this, then you'll have to provide it to the `init.sh` script later.

## One time setup

- Configure an `environments/{environment_name}.yml` var file. 
  - Use [environments/example.yml](environments/example.yml) as a reference. See comments in file for details.
- Run the `init.sh` script providing the var file above as one of the inputs.
    ```
        # If you create a PVE_ROOT_PASSWORD.env file under Prerequisites...
        # {var_file} = 'environments/yourvarfile.yml'
        # {user} = 'root' # Or whatever you configured your proxmox root user as
        ./init.sh {var_file} {user}

        # If not, then provide the password now.
        # {password} is the password for the root Proxmox {user}.
        PVE_ROOT_PASSWORD='{password}' ./init.sh {var_file} {user}
    ```

What this did:
- Setup a new python environment and download all the requirments.
- Created an Api Token for each Proxmox node
- Saved it to the `api_token_export` location specified in your var file. (Example: `$HOME/environment_vars/PVE_HOST01_API_TOKEN.env`)

## Changing API Tokens

If a Proxmox Api Token needs to be reset / renewed, then you can simply delete the old one from your the Proxmox website under Datacenter -> API tokens.  Then run this script again and it will create new ones and update your api token environment files. If you don't delete them first, this script will fail with an error message that should be obvious, something like "Api Token already exists".

## Updating / Recreate Python Environment
- Run the `./init-py.sh` script. 

No need to run the `init.sh` script again, as you'll like encounter errors from existing proxmox API tokens.
# install az CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash


# Install .NET 9.0 runtime if not present
sudo add-apt-repository ppa:dotnet/backports
# install SDK
sudo apt-get update && \
  sudo apt-get install -y dotnet-sdk-9.0
# install runtime
sudo apt-get update && \
  sudo apt-get install -y aspnetcore-runtime-9.0
# verify
dotnet --list-runtimes | grep 'Microsoft.AspNetCore.App 9.0'

sudo rm -f /usr/share/keyrings/packages.microsoft.gpg
sudo rm -f /etc/apt/sources.list.d/mssql-tools.list

# install sqlcmd
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
# echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mssql-tools.list >/dev/null
# use the 22.04 repo for 24.04 until 24.04 is supported
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" | sudo tee /etc/apt/sources.list.d/mssql-tools.list >/dev/null
sudo apt-get update
sudo apt install mssql-tools unixodbc-dev -y
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
# verify
sqlcmd -?
# execute seed planets sql script example
sqlAdminPassword='***'
sqlcmd -S sqlnascmieoldevaue.database.windows.net -d planetsdb -u sqladminuser -P $sqlAdminPassword

## execute the runner in background
nohup ./run.sh &
# to kill  the process triggered by nohup, identify the PID executing run.sh, then call kill <PID>
ps aux | grep run.sh
kill <PID> 
# if the runners are still showing in GH runners dashboard, you may need to restart the GH runner VMs

## run the GH runner as a service
# install
sudo ./svc.sh install
# start
sudo ./svc.sh start
# check status
sudo ./svc.sh status
# stop
sudo ./svc.sh stop
# uninstall
sudo ./svc.sh uninstall

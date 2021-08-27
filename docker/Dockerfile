#CloudMethods Dockerfile v1.1
#Dockerfile to build custom powercli coainer for Amazon linux 2 build with Packer
FROM mcr.microsoft.com/powershell:latest
RUN apt-get update && DEBIAN_FRONTEND=noninteractive && apt-get install -y bash && apt-get clean
# Set working directory so stuff doesn't end up in /
WORKDIR /root
# Install VMware modules from PSGallery
SHELL [ "pwsh", "-command" ]
RUN Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
RUN Install-Module VMware.PowerCLI,PowerNSX,PowervRA
# Add the PowerCLI Example Scripts and Modules
# using ZIP instead of a git pull to save at least 100MB
SHELL ["bash", "-c"]
RUN mkdir /usr/local/share/powershell/Modules && \
CMD ["/usr/bin/pwsh"]

# Heapy
Extract strings and credentials from processes
[![License](https://img.shields.io/badge/license-MIT-_red.svg)](https://opensource.org/licenses/MIT)  
<img src="https://github.com/dokDork/Heapy/raw/main/images/heapy.png" width="250" height="250">  


## Disclaimer
This tool is provided for authorized security testing, research, and educational purposes only.
If you use this tool for any activity involving attacks, exploitation, or security testing against individuals, companies, systems, or networks, you must have explicit prior authorization from the relevant person, organization, or asset owner.

Unauthorized use is strictly prohibited. The author assumes no responsibility for any misuse or damage caused by this tool.
  
## Description
**Heapy** analyzes active processes and, for each process it can access, retrieves from memory any strings and credentials it is able to find, generating output files containing the information it was able to recover.
  
## Example Usage
 ```
./heapy.py -l 10
 ``` 
  
## How to install it on Kali Linux (or Debian distribution)
It's very simple  
```
cd /opt
sudo git clone https://github.com/dok72/Heapy.git
cd Heapy 
chmod 755 heapy.py 
./heapy.sh
```

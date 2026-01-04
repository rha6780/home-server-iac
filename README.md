# home-server-iac

![Terraform](https://img.shields.io/badge/terraform-1.14.0-purple)
![SemaPhore](https://img.shields.io/badge/semaphore-v.2.16.47-green)



개인 홈서버 구축을 위한 IAC 프로젝트 입니다.


Terraform 을 이용해서 기본적인 인프라 세팅을 진행합니다.
이후, 반복적인 과정(VM 생성) 등에 대해서는 ansible 등을 이용하여 진행합니다.

기본적으로 홈 서버는 Proxmox 를 이용하여 구성되며, Terraform - proxmox - ansible로 연동 설정이 되어있습니다. 


terraform-provider 는 telmate/proxmox 를 사용합니다.


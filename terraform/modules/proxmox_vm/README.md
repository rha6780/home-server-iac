<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bridge"></a> [bridge](#input\_bridge) | 네트워크 브릿지 | `string` | `"vmbr0"` | no |
| <a name="input_cores"></a> [cores](#input\_cores) | CPU 코어 수 | `number` | `2` | no |
| <a name="input_cpu_type"></a> [cpu\_type](#input\_cpu\_type) | CPU 타입 | `string` | `"x86-64-v2-AES"` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | 디스크 크기 (예: 20G) | `string` | `"20G"` | no |
| <a name="input_macaddr"></a> [macaddr](#input\_macaddr) | 네트워크 MAC 주소 (null이면 Proxmox 자동 할당) | `string` | `null` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | 메모리 (MB) | `number` | `2048` | no |
| <a name="input_name"></a> [name](#input\_name) | VM 이름 | `string` | n/a | yes |
| <a name="input_notes"></a> [notes](#input\_notes) | VM 추가 설명 (공통 포맷 외 추가 내용) | `string` | `""` | no |
| <a name="input_sockets"></a> [sockets](#input\_sockets) | CPU 소켓 수 | `number` | `1` | no |
| <a name="input_start_at_node_boot"></a> [start\_at\_node\_boot](#input\_start\_at\_node\_boot) | 노드 부팅 시 자동 시작 | `bool` | `true` | no |
| <a name="input_storage"></a> [storage](#input\_storage) | 스토리지 풀 | `string` | `"local-lvm"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | VM 태그 | `string` | `""` | no |
| <a name="input_target_node"></a> [target\_node](#input\_target\_node) | Proxmox 노드 이름 | `string` | `"pve-main"` | no |
| <a name="input_vmid"></a> [vmid](#input\_vmid) | Proxmox VM ID | `number` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Terraform 리소스 ID |
| <a name="output_name"></a> [name](#output\_name) | VM 이름 |
| <a name="output_vmid"></a> [vmid](#output\_vmid) | Proxmox VM ID |
<!-- END_TF_DOCS -->
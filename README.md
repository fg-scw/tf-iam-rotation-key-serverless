# Scaleway API Key Rotation with Terraform

Automated API key rotation system for Scaleway using serverless functions. This infrastructure automatically creates new API keys, stores them securely in Secret Manager, and provides easy retrieval.

## Overview

This project deploys:
- **Rotation Function**: Creates new API keys and stores them in Secret Manager
- **Retrieval Function**: Fetches stored API keys for your applications
- **Scheduled Rotation**: Monthly automatic key rotation via CRON trigger

## Prerequisites

- Terraform >= 1.0
- Scaleway account with the following services enabled:
  - Serverless Functions
  - Secret Manager
  - IAM

## Quick Start

1. **Clone and configure**
   ```bash
   git clone <your-repo>
   cd scaleway-api-rotation
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars** with your Scaleway credentials:
   ```hcl
   scw_access_key      = "SCW..."
   scw_secret_key      = "your-secret-key"
   scw_project_id      = "your-project-id"  
   scw_organization_id = "your-org-id"
   scw_region          = "fr-par"
   prefix              = "my-rotation"
   ```

3. **Deploy**
   ```bash
   terraform init
   terraform apply
   ```

## Usage

After deployment, you'll get two function URLs:

### Manual Key Rotation
```bash
curl -X POST https://your-rotation-function-url
```

### Retrieve Current Keys
```bash
curl -X GET https://your-retrieval-function-url
```

Example response:
```json
{
  "API_KEY": "SCW...",
  "SECRET_KEY": "your-new-secret-key"
}
```

## Configuration

### Rotation Schedule
Default: 1st of each month at 2 AM
```hcl
cron_schedule = "0 2 1 * *"
```

Common alternatives:
- Weekly: `"0 2 * * 0"` (Sunday 2 AM)
- Bi-weekly: `"0 2 1,15 * *"` (1st and 15th at 2 AM)

### Function Resources
```hcl
rotation_memory_limit  = 256  # MB
rotation_timeout      = 300  # seconds
retrieval_memory_limit = 128  # MB  
retrieval_timeout     = 60   # seconds
```

## Integration Example

```python
import requests

def get_current_api_keys():
    response = requests.get('https://your-retrieval-function-url')
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Failed to retrieve keys: {response.text}")

# Usage
keys = get_current_api_keys()
scw_access_key = keys['API_KEY']
scw_secret_key = keys['SECRET_KEY']
```

## Monitoring

### View Function Logs
1. Go to Scaleway Console → Functions
2. Select your namespace (prefix + "-namespace")
3. Click on function → Logs tab

### Common Issues
- **403 Errors**: Check IAM permissions for Secret Manager and Functions
- **Timeout**: Increase function timeout in variables
- **Memory Issues**: Increase memory limits

## Security Notes

- Keys are stored encrypted in Scaleway Secret Manager
- Functions use environment variables for authentication
- All API calls use HTTPS
- Old keys are not automatically deleted (manual cleanup recommended)

## File Structure

```
.
├── main.tf                    # Main Terraform configuration
├── terraform.tfvars.example  # Configuration template
├── functions/
│   ├── rotation/handler.py   # Key rotation logic
│   └── retrieval/handler.py  # Key retrieval logic
└── README.md
```

## Cleanup

To remove all resources:
```bash
terraform destroy
```

**Note**: This will not delete the secrets stored in Secret Manager. Clean those manually if needed.

## Troubleshooting

### Function Not Found
Ensure your Scaleway credentials have the necessary permissions and the project ID is correct.

### Secret Already Exists Error  
This is normal - the function will update the existing secret with new key versions.

### API Rate Limits
The rotation function includes appropriate delays between API calls to respect rate limits.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

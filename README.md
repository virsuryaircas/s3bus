# S3Bus - S3 Bucket Size Analyzer

CLI utility to see `s3 bucket size` without opening the AWS Console.

## 📸 Screenshot

![ENV2YAML Screenshot](https://raw.githubusercontent.com/virsuryaircas/s3bus/main/s3bus-cli-screenshot.png)


## ✨ Features

- List all S3 buckets
- Get individual bucket size
- Tabulation view of buckets
- Total no of buckets count
- Total bucket storage summary

### ⚙️ Pre-Requirements (AWS CLI)

Commands to install AWS CLI in linux

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

### 🔧 Configure AWS Credentials

Input your AWS Credentials in `env.local`

```env
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```

## 👨‍🔧 Usage

```bash
curl 
chmod +x s3bus.sh
./s3bus.sh
```

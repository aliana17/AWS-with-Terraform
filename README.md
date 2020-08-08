# AWS-with-Terraform
Building Infrastructure as a code on AWS using Terraform

If you have worked on Terraform, you may have founded tedious task to go to different services mannually on GUI and configure them for your application. 
Terraform helps us in automating things we do in GUI. 

The Terraform code here will 
* create an EC2 instance which has httpd server configured before booting. 
* create an EBS volume 
* attach this volume to the instance created above
* create S3 bucket to store images for the application
* configure cloudfront for s3 so as to reduce latency while accessing these images. 
* update application code to use this cloudfront url dynamically. 

You can check for step- wise procedure from this blog

https://medium.com/@agarwalanchal72/infrastructure-as-code-with-terraform-7b63bbbd1dd8
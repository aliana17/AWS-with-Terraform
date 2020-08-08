provider "aws"{
    region = "ap-south-1"
    profile = "websecret"
}

//Generates a secure private key and encodes it as PEM.
resource "tls_private_key" "my_key" {
  algorithm   = "RSA"
}

//Provides an EC2 key pair resource.
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.my_key.public_key_openssh
  
  depends_on = [
    tls_private_key.my_key
  ]
}

//Saving Private Key PEM File
resource "local_file" "key-file" {
  content  = tls_private_key.my_key.private_key_pem
  filename = "wev-key.pem"
  
  depends_on = [
    tls_private_key.my_key
  ]
}

//Creating Security Group
resource "aws_security_group" "web_SG" {
  name        = "SG_Terraform"
  description = "Security Group for Terraform"


  //Adding Rules  
  ingress {
    description = "SSH Rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "HTTP Rule"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Creating Variable for AMI_ID 
variable "ami_id" {
  type    = string
  default = "ami-0447a12f28fddb066"
}

//Creating Variable for AMI_Type
variable "ami_type" {
  type    = string
  default = "t2.micro"
}

resource "aws_instance" "web" {
  ami = var.ami_id
  instance_type = var.ami_type
  key_name = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.web_SG.name,"default"]

  tags = {
    Name = "Web"
    env  = "Production"
  } 

  depends_on = [
    aws_security_group.web_SG,
    aws_key_pair.deployer
  ]

  
//Installing Softwares in our instance.
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]

//Estabilishing connection with our instance.
  connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = tls_private_key.my_key.private_key_pem
      host   = aws_instance.web.public_ip
    }
  }

 //Put CloudFront URLs in our Website Code
  provisioner "local-exec" {
    command = "sed -i 's/\CF_URL_Here/${aws_cloudfront_distribution.s3-web-distribution.domain_name}/g' index.html"
  }

  provisioner "file" {
    connection {
      agent       = false
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.my_key.private_key_pem}"
      host        = "${aws_instance.web.public_ip}"
    }

    source      = "index.html"
    destination = "/home/ec2-user/index.html" 
  }
}

resource "aws_ebs_volume" "myebs1" {
    depends_on = [
        aws_instance.web
    ]
  availability_zone = aws_instance.web.availability_zone
  size         = 1

  tags = {
    Name = "web_Server_vol"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  depends_on = [
      aws_ebs_volume.myebs1,
  ]
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.myebs1.id}"
  instance_id = "${aws_instance.web.id}"
}

resource "null_resource" "useebs" {

  depends_on = [
    aws_volume_attachment.ebs_att,
  ]

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo cp /home/ec2-user/index.html  /var/www/html/",
    ]
    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = tls_private_key.my_key.private_key_pem
      host   = aws_instance.web.public_ip
    }
  }
}

resource "aws_s3_bucket" "image_store" {
  bucket = "tf-test-bucket1234"
  acl    = "public-read"
  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_object" "data" {
  bucket = aws_s3_bucket.image_store.bucket
  key    = "webimage.jpg"
  source = "congratulations.jpg"
  acl = "public-read"
}

//Creating CloutFront with S3 Bucket Origin
resource "aws_cloudfront_distribution" "s3-web-distribution" {
  origin {
    domain_name = "${aws_s3_bucket.image_store.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.image_store.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 Web Distribution"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.image_store.id}"


    forwarded_values {
      query_string = false  


      cookies {
        forward = "none"
      }
    }


    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"] 
    }
  }


  tags = {
    Name        = "Web-CF-Distribution"
    Environment = "Production"
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }


  depends_on = [
    aws_s3_bucket.image_store
  ]
}

//saving Ip of our instance in a file
resource "null_resource" "saveIP"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
  	}

  depends_on = [
        aws_instance.web
  ]
}
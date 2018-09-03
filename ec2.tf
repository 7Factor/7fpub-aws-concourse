resource "aws_instance" "concourse_web" {
  count = "${var.web_count}"

  ami           = "${data.aws_ami.aws_linux.id}"
  instance_type = "${var.web_instance_type}"

  # We're doing some magic here to allow for any number of count that's evenly distributed
  # across the configured subnets.
  subnet_id = "${var.web_private_subnets[count.index % length(var.web_private_subnets)]}"

  key_name = "${var.conc_ssh_key_name}"

  vpc_security_group_ids = [
    "${aws_security_group.web_sg.id}",
    "${var.utility_accessible_sg}",
  ]

  tags {
    Name    = "Concourse Web"
    Cluster = "${var.cluster_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/concourse/keys",
      "sudo chown -R ec2-user:ec2-user /etc/concourse",
      "mkdir -p ~/keys",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }

  provisioner "file" {
    source      = "${var.web_keys_dir}"
    destination = "~/keys/"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum -y install docker",
      "sudo service docker start",
      "sudo usermod -aG docker ec2-user",
      "sudo docker pull ${var.conc_image}",
      "sudo mv ~/keys /etc/concourse/",
      "sudo find /etc/concourse/keys/ -type f -exec chmod 400 {} \\;",
      "sudo docker run -d --network host --name concourse_web --restart=unless-stopped -v /etc/concourse/keys/:/concourse-keys ${var.conc_image} web --peer-url http://${self.private_ip}:8080 --postgres-host ${var.concoursedb_host} --postgres-port ${var.concoursedb_port} --postgres-user ${var.concoursedb_user} --postgres-password ${var.concoursedb_pass} --postgres-database ${var.concoursedb_database} --external-url ${var.fqdn} ${var.authentication_config} ${var.web_launch_options}",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }
}

#---------------------------------------------------------
# Concourse worker farm.
#---------------------------------------------------------
resource "aws_instance" "concourse_worker" {
  count      = "${var.worker_count}"
  depends_on = ["aws_elb.concourse_lb"]

  ami           = "${data.aws_ami.aws_linux.id}"
  instance_type = "${var.worker_instance_type}"

  # We're doing some magic here to allow for any number of count that's evenly distributed
  # across the configured subnets.
  subnet_id = "${var.worker_subnets[count.index % length(var.worker_subnets)]}"

  key_name = "${var.conc_ssh_key_name}"

  vpc_security_group_ids = [
    "${var.utility_accessible_sg}",
    "${aws_security_group.worker_sg.id}",
  ]

  tags {
    Name    = "Concourse Worker"
    Cluster = "${var.cluster_name}"
  }

  root_block_device {
    volume_size = "${var.worker_vol_size}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/concourse/keys",
      "sudo chown -R ec2-user:ec2-user /etc/concourse",
      "mkdir -p ~/keys",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }

  provisioner "file" {
    source      = "${var.worker_keys_dir}"
    destination = "~/keys/"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update",
      "sudo yum -y install docker",
      "sudo service docker start",
      "sudo usermod -aG docker ec2-user",
      "sudo docker pull ${var.conc_image}",
      "sudo mv ~/keys /etc/concourse/",
      "sudo find /etc/concourse/keys/ -type f -exec chmod 400 {} \\;",
      "sudo docker run -d --network host --name concourse_worker --privileged=true --restart=unless-stopped -v /etc/concourse/keys/:/concourse-keys -v /tmp/:/concourse-tmp ${var.conc_image} worker --bind-ip ${var.worker_bind_ip} --baggageclaim-bind-ip ${var.worker_bind_ip} --garden-bind-ip ${var.worker_bind_ip} --peer-ip ${self.private_ip} --tsa-host ${aws_elb.concourse_lb.dns_name}:2222 --work-dir /concourse-tmp ${var.worker_launch_options}",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = "${self.private_ip}"
      private_key = "${file("${path.root}/keys/${var.conc_ssh_key_name}.pem")}"
    }
  }
}

# TerraformAWS
# TerrExample

## 1. Instalar Terraform

wget https://releases.hashicorp.com/terraform/0.11.9/terraform_0.11.9_linux_amd64.zip

unzip terraform_0.11.9_linux_amd64.zip

sudo mv terraform /usr/local/bin/

gedit .bashrc: export PATH=$PATH:/usr/local/bin/

terraform --version 

## 2. Configurar, plan y apply!

Comenzar con una definición básica de contenedor de ami en una configuración mínima de Terraform: crear un archivo example.tf:

```hcl
provider "aws" {
  access_key = "ACCESS_KEY_HERE"
  secret_key = "SECRET_KEY_HERE"
  region     = "us-east-1"
}

resource "aws_instance" "example" {
  ami           = "ami-2757f631"
  instance_type = "t2.micro"
}
```

Vamos a colocar un archivo llamado variable.tf, de donde se van a expecificar ciertas variables que se va a necesitar.
El archvivo AWSKeyDavid.pem tenemos que generarlo en los key Pairs de las instancias de EC2.

```hcl
variable "count" {
  default = 1
}

variable "region" {
  description = "AWS region for hosting our your network"
  default     = "us-east-1"
}

variable "public_key_path" {
  description = "Enter the path to the SSH Public Key to add to AWS."
  default     = "/home/david/terraform/key/AWSKeyDavid.pem"
}

variable "key_name" {
  description = "Key name for SSHing into EC2"
  default     = "AWSKeyDavid"
}

variable "amis" {
  description = "Base AMI to launch the instances"

  default = {
    us-east-1 = "ami-2757f631"
  }
}
```

##  2.1 Dando un *Auto Scaling Group*

Los grupos de escalado automático (ASG) pueden proporcionar automáticamente más instancias de nuestro microservicio cuando aumentan las cargas. Para poder proporcionar un ASG dentro de nuestro archivo terraform, primero deberemos crear un Grupo de Seguridad de AWS que especifique las reglas de puertos de ingreso y egreso para cada instancia dentro de nuestro ASG.

```hcl
### Configure AWS provider
provider "aws" {
  access_key = "ACCESS_KEY_HERE"
  secret_key = "SECRET_KEY_HERE"
  region     = "us-east-1"
}

data "aws_availability_zones" "all" {}

### Creating EC2 instance
resource "aws_instance" "web" {
  ami = "${lookup(var.amis,var.region)}"

  #ami                    = "ami-2757f631"
  count                  = "${var.count}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.instance.id}"]
  source_dest_check      = false
  instance_type          = "t2.micro"

  tags {
    Name = "${format("web-%03d", count.index + 1)}"
  }
}

### Creating Security Group for EC2
### Crear esto antes de crear un ASG
resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Creating Launch Configuration
resource "aws_launch_configuration" "example" {
  image_id = "${lookup(var.amis,var.region)}"

  #image_id        = "ami-58d7e821"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.instance.id}"]
  key_name        = "${var.key_name}"

  #user_data       = "${file("setup.sh")}"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF
  lifecycle {
    create_before_destroy = true
  }
}
```
Al finalizar creará un archivo index.html que sera accesible al ingresar a la direccion web.


## 2.2 Configurando un *Elastic Load Balancer*

Con el fin de proveer un Elastic Load Balancer (ELB) que distribuye automáticamente el tráfico entrante a través de múltiples objetivos, que primero tendrá que crear un recurso de grupo de seguridad y especificar tanto las reglas *ingress* como *egress* en la lista blanca, las direcciones IP y los puertos de tráfico entrante y saliente.

Una vez que hemos especificado el grupo de seguridad, podemos seguir adelante y dictar la configuración de nuestro ELB. Podemos especificar en cuáles *availability_zones* implementar nuestras instancias t2.micro, así como los escuchas y las comprobaciones de estado de nuestro equilibrador de carga para evitar que nuestros usuarios se vean afectados.

```hcl
## Creating AutoScaling Group
resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.example.id}"
  availability_zones   = ["${data.aws_availability_zones.all.names}"]
  min_size             = 2
  max_size             = 5
  load_balancers       = ["${aws_elb.example.name}"]
  health_check_type    = "ELB"

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

## Security Group for ELB
resource "aws_security_group" "elb" {
  name = "terraform-example-elb"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Creating ELB
resource "aws_elb" "example" {
  name               = "terraform-asg-example"
  security_groups    = ["${aws_security_group.elb.id}"]
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:8080/"
  }

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "8080"
    instance_protocol = "http"
  }
}
```

En el archivo output.tf final , también especificaremos que nuestro comando *terraform apply* debe generar el registro final de ELB, que nos informará cómo llegar a nuestro servicio recién implementado.

```hcl
output "instance_ids" {
  value = ["${aws_instance.web.*.public_ip}"]
}

output "elb_dns_name" {
  value = "${aws_elb.example.dns_name}"
}

```

+ Una vez que se ha definido la configuración, necesitamos crear un plan de ejecución. Terraform describe las acciones requeridas para lograr el estado deseado. El plan se puede guardar usando -out. Aplicaremos el plan de ejecución en el siguiente paso.

```
sudo terraform plan -out config.tfplan
```

+ Creado el plan, debemos aplicarlo para alcanzar el estado deseado. Usando el CLI, terraform extraerá cualquier imagen requerida y lanzará nuevos contenedores. La salida indicará los cambios y la configuración resultante.

```
sudo terraform apply
```

- Podemos revisar el ejemplo en:

[Click para ir al ejemplo](http://terraform-asg-example-1628040009.us-east-1.elb.amazonaws.com)


Tambien podemos revisar las configuraciones y cambios futuros:

```
sudo terraform show
```


## 3. Otras herramientas similares

- Las herramientas de orquestación de configuración, que incluyen Terraform y AWS CloudFormation, están diseñadas para automatizar la implementación de servidores y otra infraestructura.

- Las herramientas de administración de la configuración como Chef, Puppet y las demás en esta lista ayudan a configurar el software y los sistemas en esta infraestructura que ya se ha aprovisionado.

### 3.1 AWS CloudFormation

<img src="https://dnp94fjvlna2x.cloudfront.net/wp-content/uploads/2018/04/CF-logo.png" width="128">

Al igual que Terraform, AWS CloudFormation es una herramienta de orquestación de configuración que le permite codificar su infraestructura para automatizar sus implementaciones.

Las principales diferencias radican en que CloudFormation está profundamente integrado y solo se puede utilizar con AWS, y las plantillas de CloudFormation se pueden crear con YAML además de JSON.

CloudFormation le permite obtener una vista previa de los cambios propuestos en su pila de infraestructura de AWS y ver cómo podrían afectar sus recursos, y administra las dependencias entre estos recursos.

Para garantizar que la implementación y actualización de la infraestructura se realice de manera controlada, CloudFormation usa Desencadenadores de reversión para revertir las pilas de infraestructura a un estado implementado anterior si se detectan errores.

### 3.2 Azure Resource Manager y Google Cloud Deployment Manager

**Azure Resource Manager** le permite definir la infraestructura y las dependencias para su aplicación en plantillas, organizar recursos dependientes en grupos que se pueden implementar o eliminar en una sola acción, controlar el acceso a los recursos a través de los permisos de los usuarios y más.
<center>
<img src="https://dnp94fjvlna2x.cloudfront.net/wp-content/uploads/2018/04/azure-resource-manager.jpg" width="128">
</center>

**Google Cloud Deployment Manager**  ofrece muchas características similares para automatizar su pila de infraestructura GCP. Puede crear plantillas utilizando YAML o Python, obtener una vista previa de los cambios que se realizarán antes de la implementación, ver sus implementaciones en la interfaz de usuario de la consola y mucho más.

<center>
<img src="https://dnp94fjvlna2x.cloudfront.net/wp-content/uploads/2018/04/Deployment_Manager.png" width="128">
</center>
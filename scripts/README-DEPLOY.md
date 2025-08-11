# Sistema de Deploy ECS - Projeto BIA

Este sistema de deploy foi criado especificamente para o projeto BIA, seguindo as melhores práticas de versionamento e deploy para ECS.

## 🚀 Características Principais

- **Versionamento por Commit Hash**: Cada imagem é taggeada com os primeiros 8 caracteres do commit hash
- **Rollback Simples**: Possibilidade de voltar para qualquer versão anterior
- **Task Definition Versionada**: Cada deploy cria uma nova revisão da task definition
- **Deploy Atômico**: O serviço só é atualizado após a imagem estar pronta
- **Logs Coloridos**: Interface amigável com feedback visual

## 📋 Pré-requisitos

- AWS CLI configurado com credenciais válidas
- Docker instalado e rodando
- jq instalado (`sudo yum install jq`)
- Estar no diretório raiz do projeto (onde está o Dockerfile)
- Repositório ECR criado
- Cluster ECS e serviço já configurados

## 🛠️ Instalação

O script já está pronto para uso. Apenas certifique-se de que tem as permissões necessárias:

```bash
# Tornar executável (já feito)
chmod +x scripts/deploy-ecs.sh
chmod +x deploy.sh
```

## 📖 Como Usar

### Opção 1: Script Direto
```bash
# Deploy completo (build + deploy)
./scripts/deploy-ecs.sh deploy

# Apenas build da imagem
./scripts/deploy-ecs.sh build

# Rollback para versão específica
./scripts/deploy-ecs.sh rollback --tag abc12345

# Listar versões disponíveis
./scripts/deploy-ecs.sh list
```

### Opção 2: Script Wrapper (Recomendado)
```bash
# Deploy completo
./deploy.sh deploy

# Rollback
./deploy.sh rollback --tag abc12345

# Ajuda
./deploy.sh help
```

### Opção 3: Com Configurações Personalizadas
```bash
# Copiar arquivo de configuração
cp scripts/deploy-config.example scripts/deploy-config

# Editar configurações
nano scripts/deploy-config

# Deploy usando as configurações
./deploy.sh deploy
```

## 🔧 Configurações

### Configurações Padrão
- **Região**: us-east-1
- **Cluster**: bia-cluster-alb
- **Serviço**: bia-service
- **Task Family**: bia-tf
- **ECR Repo**: bia

### Personalizando Configurações
```bash
# Via parâmetros
./deploy.sh deploy --region us-west-2 --cluster meu-cluster

# Via arquivo de configuração
cp scripts/deploy-config.example scripts/deploy-config
# Edite o arquivo e execute
./deploy.sh deploy
```

## 📝 Exemplos de Uso

### Deploy Básico
```bash
# Fazer commit das mudanças
git add .
git commit -m "Nova funcionalidade"

# Deploy automático
./deploy.sh deploy
```

### Deploy com Configurações Específicas
```bash
./deploy.sh deploy \
  --region us-west-2 \
  --cluster producao-cluster \
  --service producao-service
```

### Rollback de Emergência
```bash
# Listar versões disponíveis
./deploy.sh list

# Fazer rollback
./deploy.sh rollback --tag a1b2c3d4
```

### Apenas Build (para testes)
```bash
./deploy.sh build
```

## 🔍 Troubleshooting

### Erro: "Repositório ECR não encontrado"
```bash
# Criar repositório ECR
aws ecr create-repository --repository-name bia --region us-east-1
```

### Erro: "Task definition não encontrada"
```bash
# Verificar se a task definition existe
aws ecs describe-task-definition --task-definition bia-tf
```

### Erro: "Docker não está rodando"
```bash
# Iniciar Docker
sudo systemctl start docker
```

### Erro: "jq não encontrado"
```bash
# Instalar jq
sudo yum install jq -y
```

## 🔐 Permissões IAM Necessárias

O usuário/role precisa das seguintes permissões:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:DescribeImages"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition",
                "ecs:UpdateService",
                "ecs:DescribeServices"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

## 📊 Fluxo do Deploy

1. **Verificação**: Valida dependências e configurações
2. **Login ECR**: Autentica no registry
3. **Build**: Constrói imagem com tag do commit hash
4. **Push**: Envia imagem para ECR
5. **Task Definition**: Cria nova revisão com a nova imagem
6. **Update Service**: Atualiza o serviço ECS
7. **Wait**: Aguarda estabilização do serviço

## 🎯 Vantagens do Sistema

- **Rastreabilidade**: Cada deploy é vinculado a um commit específico
- **Rollback Rápido**: Voltar para qualquer versão em segundos
- **Segurança**: Validações em cada etapa
- **Flexibilidade**: Configurável para diferentes ambientes
- **Simplicidade**: Interface amigável e intuitiva

## 🤝 Contribuindo

Para melhorar o script:

1. Faça suas modificações
2. Teste em ambiente de desenvolvimento
3. Documente as mudanças
4. Commit com mensagem descritiva

## 📞 Suporte

Em caso de problemas:

1. Verifique os logs do script (são bem detalhados)
2. Confirme as permissões IAM
3. Valide as configurações AWS
4. Teste os comandos AWS CLI manualmente

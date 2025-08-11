#!/bin/bash

# Script de Deploy ECS - Projeto BIA (Versão 2.0)
# Autor: Amazon Q
# Versão: 2.0.0

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER="cluster-bia-ia"
DEFAULT_SERVICE="bia-service"
DEFAULT_TASK_FAMILY="bia-tf"
DEFAULT_ECR_REPO="bia"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir mensagens coloridas
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função de ajuda
show_help() {
    cat << EOF
🚀 Script de Deploy ECS - Projeto BIA

USAGE:
    $0 [OPTIONS] COMMAND

COMMANDS:
    build       Constrói a imagem Docker com tag baseada no commit hash
    deploy      Faz deploy da imagem para ECS (inclui build automaticamente)
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 versões disponíveis no ECR
    help        Exibe esta ajuda

OPTIONS:
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -f, --family FAMILY         Família da task definition (padrão: $DEFAULT_TASK_FAMILY)
    -e, --ecr-repo REPO         Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -t, --tag TAG              Tag específica para rollback
    -h, --help                  Exibe esta ajuda

EOF
}

# Função para obter o commit hash
get_commit_hash() {
    if [ -d ".git" ]; then
        git rev-parse --short=8 HEAD
    else
        log_error "Não é um repositório Git. Execute o comando no diretório raiz do projeto."
        exit 1
    fi
}

# Função para obter informações da conta AWS
get_aws_account() {
    aws sts get-caller-identity --query Account --output text 2>/dev/null || {
        log_error "Erro ao obter informações da conta AWS. Verifique suas credenciais."
        exit 1
    }
}

# Função para fazer login no ECR
ecr_login() {
    local region=$1
    local account_id=$2
    
    log_info "Fazendo login no ECR..."
    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $account_id.dkr.ecr.$region.amazonaws.com
}

# Função para verificar se o repositório ECR existe
check_ecr_repo() {
    local region=$1
    local repo_name=$2
    
    aws ecr describe-repositories --region $region --repository-names $repo_name >/dev/null 2>&1 || {
        log_error "Repositório ECR '$repo_name' não encontrado na região '$region'"
        log_info "Crie o repositório com: aws ecr create-repository --repository-name $repo_name --region $region"
        exit 1
    }
}

# Função para construir a imagem
build_image() {
    local region=$1
    local ecr_repo=$2
    local commit_hash=$3
    local account_id=$4
    
    local image_uri="$account_id.dkr.ecr.$region.amazonaws.com/$ecr_repo:$commit_hash"
    
    log_info "Construindo imagem Docker..."
    log_info "Tag: $commit_hash"
    log_info "URI: $image_uri"
    
    # Verificar se Dockerfile existe
    if [ ! -f "Dockerfile" ]; then
        log_error "Dockerfile não encontrado no diretório atual"
        exit 1
    fi
    
    # Build da imagem
    docker build -t $image_uri . || {
        log_error "Falha no build da imagem Docker"
        exit 1
    }
    
    # Push da imagem
    log_info "Enviando imagem para ECR..."
    docker push $image_uri || {
        log_error "Falha no push da imagem para ECR"
        exit 1
    }
    
    log_success "Imagem construída e enviada: $image_uri"
    echo $image_uri
}

# Função para verificar se task definition existe
task_definition_exists() {
    local region=$1
    local family=$2
    
    aws ecs describe-task-definition --region $region --task-definition $family >/dev/null 2>&1
}

# Função para criar task definition básica usando arquivo temporário
create_basic_task_definition() {
    local region=$1
    local family=$2
    local image_uri=$3
    local account_id=$4
    
    # Criar o log group se não existir
    aws logs create-log-group --log-group-name "/ecs/$family" --region $region 2>/dev/null || true
    
    # Criar arquivo JSON temporário
    cat > /tmp/task-definition-template.json << EOF
{
    "family": "$family",
    "networkMode": "bridge",
    "requiresCompatibilities": ["EC2"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::$account_id:role/ecsTaskExecutionRole",
    "containerDefinitions": [
        {
            "name": "bia-container",
            "image": "$image_uri",
            "memory": 512,
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 8080,
                    "protocol": "tcp"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/$family",
                    "awslogs-region": "$region",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                },
                {
                    "name": "PORT",
                    "value": "8080"
                }
            ]
        }
    ]
}
EOF
    
    echo "/tmp/task-definition-template.json"
}

# Função para criar nova task definition
create_task_definition() {
    local region=$1
    local family=$2
    local image_uri=$3
    local account_id=$4
    
    local task_def_file
    
    if task_definition_exists $region $family; then
        log_info "Atualizando task definition existente..."
        
        # Obter task definition atual
        aws ecs describe-task-definition --region $region --task-definition $family --query 'taskDefinition' --output json > /tmp/current-task-def.json
        
        # Atualizar apenas a imagem usando jq
        jq --arg image "$image_uri" '
            .containerDefinitions[0].image = $image |
            del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
        ' /tmp/current-task-def.json > /tmp/updated-task-def.json
        
        task_def_file="/tmp/updated-task-def.json"
    else
        log_info "Criando nova task definition básica..."
        task_def_file=$(create_basic_task_definition $region $family $image_uri $account_id)
    fi
    
    log_info "Registrando nova task definition..."
    
    # Registrar task definition usando arquivo
    local result=$(aws ecs register-task-definition --region $region --cli-input-json file://$task_def_file --output json)
    local new_revision=$(echo "$result" | jq -r '.taskDefinition.revision')
    
    if [ "$new_revision" != "null" ] && [ -n "$new_revision" ]; then
        log_success "Nova task definition registrada: $family:$new_revision"
        echo "$family:$new_revision"
    else
        log_error "Falha ao registrar task definition. Verifique o arquivo $task_def_file"
        cat $task_def_file
        exit 1
    fi
}

# Função para verificar se o cluster ECS existe
cluster_exists() {
    local region=$1
    local cluster=$2
    
    aws ecs describe-clusters --region $region --clusters $cluster --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"
}

# Função para verificar se o serviço ECS existe
service_exists() {
    local region=$1
    local cluster=$2
    local service=$3
    
    aws ecs describe-services --region $region --cluster $cluster --services $service --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"
}

# Função para atualizar o serviço ECS
update_service() {
    local region=$1
    local cluster=$2
    local service=$3
    local task_definition=$4
    
    if ! cluster_exists $region $cluster; then
        log_error "Cluster '$cluster' não encontrado na região '$region'"
        log_info "Crie o cluster primeiro através do console AWS ou CloudFormation"
        return 1
    fi
    
    if service_exists $region $cluster $service; then
        log_info "Atualizando serviço ECS existente..."
        aws ecs update-service --region $region --cluster $cluster --service $service --task-definition $task_definition >/dev/null
        
        log_info "Aguardando estabilização do serviço..."
        aws ecs wait services-stable --region $region --cluster $cluster --services $service
        
        log_success "Serviço atualizado com sucesso!"
    else
        log_warning "Serviço '$service' não encontrado no cluster '$cluster'"
        log_info "Você precisa criar o serviço ECS primeiro através do console ou CloudFormation"
        log_info "Task definition '$task_definition' foi registrada e está pronta para uso"
    fi
}

# Função para listar versões disponíveis
list_versions() {
    local region=$1
    local ecr_repo=$2
    
    log_info "Listando últimas 10 versões disponíveis no ECR:"
    aws ecr describe-images --region $region --repository-name $ecr_repo --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' --output table
}

# Função para fazer rollback
rollback() {
    local region=$1
    local cluster=$2
    local service=$3
    local family=$4
    local ecr_repo=$5
    local tag=$6
    local account_id=$7
    
    if [ -z "$tag" ]; then
        log_error "Tag não especificada para rollback. Use --tag TAG"
        exit 1
    fi
    
    local image_uri="$account_id.dkr.ecr.$region.amazonaws.com/$ecr_repo:$tag"
    
    # Verificar se a imagem existe
    aws ecr describe-images --region $region --repository-name $ecr_repo --image-ids imageTag=$tag >/dev/null 2>&1 || {
        log_error "Imagem com tag '$tag' não encontrada no ECR"
        exit 1
    }
    
    log_info "Fazendo rollback para versão: $tag"
    
    # Criar nova task definition com a imagem de rollback
    local new_task_def=$(create_task_definition $region $family $image_uri $account_id)
    
    # Atualizar serviço
    update_service $region $cluster $service $new_task_def
    
    log_success "Rollback concluído para versão: $tag"
}

# Função principal de deploy
deploy() {
    local region=$1
    local cluster=$2
    local service=$3
    local family=$4
    local ecr_repo=$5
    local account_id=$6
    local commit_hash=$7
    
    # Build da imagem
    local image_uri=$(build_image $region $ecr_repo $commit_hash $account_id)
    
    # Criar nova task definition
    local new_task_def=$(create_task_definition $region $family $image_uri $account_id)
    
    # Atualizar serviço
    update_service $region $cluster $service $new_task_def
    
    log_success "Deploy concluído!"
    log_info "Versão deployada: $commit_hash"
    log_info "Task Definition: $new_task_def"
    log_info "Imagem: $image_uri"
}

# Parse dos argumentos
REGION=$DEFAULT_REGION
CLUSTER=$DEFAULT_CLUSTER
SERVICE=$DEFAULT_SERVICE
FAMILY=$DEFAULT_TASK_FAMILY
ECR_REPO=$DEFAULT_ECR_REPO
TAG=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -f|--family)
            FAMILY="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|deploy|rollback|list|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [ -z "$COMMAND" ]; then
    log_error "Comando não especificado"
    show_help
    exit 1
fi

# Executar comando help
if [ "$COMMAND" = "help" ]; then
    show_help
    exit 0
fi

# Verificar dependências
command -v aws >/dev/null 2>&1 || { log_error "AWS CLI não encontrado"; exit 1; }
command -v docker >/dev/null 2>&1 || { log_error "Docker não encontrado"; exit 1; }
command -v jq >/dev/null 2>&1 || { log_error "jq não encontrado. Instale com: sudo yum install jq"; exit 1; }

# Obter informações da AWS
ACCOUNT_ID=$(get_aws_account)
COMMIT_HASH=$(get_commit_hash)

log_info "=== Configurações ==="
log_info "Região: $REGION"
log_info "Cluster: $CLUSTER"
log_info "Serviço: $SERVICE"
log_info "Task Family: $FAMILY"
log_info "ECR Repo: $ECR_REPO"
log_info "Account ID: $ACCOUNT_ID"
log_info "Commit Hash: $COMMIT_HASH"
log_info "===================="

# Verificar repositório ECR
check_ecr_repo $REGION $ECR_REPO

# Fazer login no ECR
ecr_login $REGION $ACCOUNT_ID

# Executar comando
case $COMMAND in
    build)
        build_image $REGION $ECR_REPO $COMMIT_HASH $ACCOUNT_ID
        ;;
    deploy)
        deploy $REGION $CLUSTER $SERVICE $FAMILY $ECR_REPO $ACCOUNT_ID $COMMIT_HASH
        ;;
    rollback)
        rollback $REGION $CLUSTER $SERVICE $FAMILY $ECR_REPO $TAG $ACCOUNT_ID
        ;;
    list)
        list_versions $REGION $ECR_REPO
        ;;
esac

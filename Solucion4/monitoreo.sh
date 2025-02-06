#!/bin/bash

# Variables
NAMESPACE=default
DEPLOYMENT_NAME=pp-pruebatecnica-669f57d5d7-4rwmt
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:18435341349120:pruebatecnica"
S3_BUCKET="minikube-logs-bucket"
LOG_DIR="/tmp/minikube_logs"

# Crear directorio si no existe
mkdir -p $LOG_DIR

while true; do
    echo "Verificando estado de los pods..."
    
    # Verificar estado de los pods
    PODS=$(kubectl get pods -n $NAMESPACE --no-headers | awk '{print $1 " " $3}')

    # Bandera para detectar fallo
    deployment_failed=false

    while read -r pod status; do
        if [[ "$status" != "Running" ]]; then
            echo "Pod $pod está en estado $status. Intentando redeploy..."
            deployment_failed=true
        fi
    done <<< "$PODS"

    # Si algún pod falló, aplicar el deployment nuevamente
    if [ "$deployment_failed" = true ]; then
        kubectl apply -f deployment.yaml -n $NAMESPACE
        sleep 30  # Esperar a que los pods se inicien

        # Revisar nuevamente si los pods están en Running
        NEW_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | awk '{print $3}')
        if echo "$NEW_PODS" | grep -q "ImagePullBackOff\|CrashLoopBackOff\|Error"; then
            echo "Error: La aplicación sigue fallando. Enviando alerta a AWS SNS..."
            MESSAGE="Fallo en Kubernetes: La aplicación $DEPLOYMENT_NAME no pudo iniciar correctamente."
            aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "$MESSAGE"
        else
            echo "El despliegue se realizó correctamente."
        fi
    else
        echo "Todos los pods están en estado Running."
    fi

    # Obtener logs de Minikube y subir a S3
    LOG_FILE="$LOG_DIR/minikube_logs_$(date +%Y%m%d%H%M%S).log"
    kubectl logs --all-namespaces > "$LOG_FILE"
    aws s3 cp "$LOG_FILE" "s3://$S3_BUCKET/"
    
    echo "Esperando 10 minutos antes de la siguiente verificación..."
    sleep 600

done

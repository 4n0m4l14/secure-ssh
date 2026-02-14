#!/bin/bash

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de log
log() {
    local level=$1
    local message=$2
    case $level in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[OK]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        *) echo "$message" ;;
    esac
}

# Función para preguntas de sí/no
prompt_confirm() {
    local question=$1
    local default=${2:-Y}
    local prompt

    if [[ "$default" == "Y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -ne "${YELLOW}$question $prompt ${NC}"
    read -r response
    
    # Si la respuesta está vacía, usar default
    if [[ -z "$response" ]]; then
        response=$default
    fi

    # Convertir a minúsculas
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

    if [[ "$response" == "y" || "$response" == "yes" ]]; then
        return 0
    else
        return 1
    fi
}

# Función para entrada de texto
prompt_input() {
    local question=$1
    local default=$2
    echo -ne "${YELLOW}$question${NC}"
    if [[ -n "$default" ]]; then
        echo -ne " [Default: $default]"
    fi
    echo -ne ": "
    read -r input

    if [[ -z "$input" ]]; then
        echo "$default"
    else
        echo "$input"
    fi
}

# Verificar root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Este script debe ejecutarse como root (o con sudo)."
        exit 1
    fi
}

# Config files
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/etc/ssh/backups"

# Crear directorio de backups
ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log "INFO" "Directorio de backups creado en $BACKUP_DIR"
    fi
}

# Backup de la configuración actual
backup_config() {
    ensure_backup_dir
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/sshd_config.backup.$timestamp"
    
    if cp "$SSHD_CONFIG" "$backup_file"; then
        log "SUCCESS" "Backup creado exitosamente: $backup_file"
    else
        log "ERROR" "Fallo al crear el backup. Abortando."
        exit 1
    fi
}

# Configurar puerto SSH
configure_port() {
    log "INFO" "Configuración del puerto SSH."
    echo "El puerto por defecto es 22. Se recomienda cambiarlo para evitar ataques automatizados."
    echo "Rango recomendado: 1024-65535."
    
    if prompt_confirm "Desea cambiar el puerto SSH?" "Y"; then
        while true; do
            read -p "Ingrese el nuevo puerto SSH: " SSH_PORT
            if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ]; then
                log "INFO" "Puerto seleccionado: $SSH_PORT"
                break
            else
                log "WARN" "Puerto inválido. Por favor ingrese un número entre 1024 y 65535."
            fi
        done
    else
        SSH_PORT=22
        log "INFO" "Manteniendo puerto por defecto: 22"
    fi
}

# Crear usuario dedicado
create_user() {
    log "INFO" "Gestión de usuarios."
    echo "Es muy recomendable NO usar root para conexiones SSH."
    
    if prompt_confirm "Desea crear un nuevo usuario con permisos sudo para SSH?" "Y"; then
        read -p "Ingrese el nombre del nuevo usuario: " NEW_USER
        
        if id "$NEW_USER" &>/dev/null; then
            log "WARN" "El usuario $NEW_USER ya existe."
        else
            useradd -m -s /bin/bash "$NEW_USER"
            log "INFO" "Creando contraseña para $NEW_USER..."
            passwd "$NEW_USER"
            usermod -aG sudo "$NEW_USER"
            log "SUCCESS" "Usuario $NEW_USER creado y añadido al grupo sudo."
        fi
        TARGET_USER="$NEW_USER"
    else
        read -p "Ingrese el usuario existente que utilizará para SSH: " TARGET_USER
        if ! id "$TARGET_USER" &>/dev/null; then
            log "ERROR" "El usuario $TARGET_USER no existe."
            exit 1
        fi
    fi
}

# Configurar llaves SSH
setup_keys() {
    log "INFO" "Configuración de autenticación por llave pública."
    local user_home=$(eval echo "~$TARGET_USER")
    local ssh_dir="$user_home/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$TARGET_USER:$TARGET_USER" "$ssh_dir"
        log "INFO" "Directorio .ssh creado para $TARGET_USER"
    fi

    if [[ ! -f "$authorized_keys" ]]; then
        touch "$authorized_keys"
        chmod 600 "$authorized_keys"
        chown "$TARGET_USER:$TARGET_USER" "$authorized_keys"
    fi

    echo "Para continuar, necesita tener su llave pública (id_rsa.pub) lista."
    echo "Opción 1: Pegar la llave pública ahora."
    echo "Opción 2: Importar desde un archivo (si lo subió previamente)."
    echo "Opción 3: Generar un par de claves nuevo (No recomendado si se conecta desde remoto)."
    echo "Opción 4: Omitir (Asume que ya configuró las llaves)."

    read -p "Seleccione una opción [1-4]: " key_option

    case $key_option in
        1)
            echo "Pegue su llave pública (comienza con ssh-rsa, ssh-ed25519, etc.):"
            read -r public_key
            if [[ -n "$public_key" ]]; then
                echo "$public_key" >> "$authorized_keys"
                log "SUCCESS" "Llave agregada a authorized_keys."
            else
                log "WARN" "Llave vacía. No se hicieron cambios."
            fi
            ;;
        2)
            read -p "Ruta absoluta al archivo de llave pública: " key_file
            if [[ -f "$key_file" ]]; then
                cat "$key_file" >> "$authorized_keys"
                log "SUCCESS" "Llave importada de $key_file."
            else
                log "ERROR" "Archivo no encontrado."
            fi
            ;;
        3)
            sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N ""
            cat "$ssh_dir/id_ed25519.pub" >> "$authorized_keys"
            log "SUCCESS" "Claves generadas. DESCARGUE LA PRIVADA: $ssh_dir/id_ed25519"
            cat "$ssh_dir/id_ed25519"
            read -p "Presione enter una vez haya guardado su clave privada..."
            ;;
        *)
            log "INFO" "Omitiendo configuración de claves."
            ;;
    esac
    
    # Asegurar permisos correctos nuevamente por si acaso
    chmod 700 "$ssh_dir"
    chmod 600 "$authorized_keys"
    chown -R "$TARGET_USER:$TARGET_USER" "$ssh_dir"
}

# Aplicar hardgening a sshd_config
harden_sshd() {
    log "INFO" "Aplicando configuración de seguridad a $SSHD_CONFIG..."
    
    # Crear una copia de trabajo
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.temp"

    # Funciones sed helpers
    set_config() {
        local param=$1
        local value=$2
        # Si existe la línea (comentada o no), reemplazarla. Si no, agregarla al final.
        if grep -q "^#\?${param}" "${SSHD_CONFIG}.temp"; then
            sed -i "s/^#\?${param}.*/${param} ${value}/" "${SSHD_CONFIG}.temp"
        else
            echo "${param} ${value}" >> "${SSHD_CONFIG}.temp"
        fi
    }

    set_config "Port" "$SSH_PORT"
    set_config "PermitRootLogin" "no"
    set_config "PubkeyAuthentication" "yes"
    set_config "PasswordAuthentication" "no"
    set_config "PermitEmptyPasswords" "no"
    set_config "ChallengeResponseAuthentication" "no"
    set_config "UsePAM" "yes"
    set_config "X11Forwarding" "no"
    set_config "PrintMotd" "no"
    set_config "MaxAuthTries" "3"
    
    # AllowUsers logic
    if ! grep -q "^AllowUsers" "${SSHD_CONFIG}.temp"; then
        echo "AllowUsers $TARGET_USER" >> "${SSHD_CONFIG}.temp"
    else
        # Si ya existe, añadir el usuario si no está
        if ! grep -q "AllowUsers.*$TARGET_USER" "${SSHD_CONFIG}.temp"; then
            sed -i "/^AllowUsers/ s/$/ $TARGET_USER/" "${SSHD_CONFIG}.temp"
        fi
    fi

    log "SUCCESS" "Configuración generada en ${SSHD_CONFIG}.temp"
}

# Configurar Firewall
configure_firewall() {
    log "INFO" "Configuración del Firewall (UFW)..."
    
    if ! command -v ufw &> /dev/null; then
        log "WARN" "UFW no está instalado. Instalándolo..."
        apt-get update && apt-get install -y ufw
    fi

    if prompt_confirm "Desea configurar UFW para permitir el puerto $SSH_PORT?" "Y"; then
        ufw allow "$SSH_PORT/tcp"
        log "SUCCESS" "Regla añadida para puerto $SSH_PORT/tcp"
        
        # Si el puerto no es 22, preguntar si bloquear el 22
        if [[ "$SSH_PORT" != "22" ]]; then
            if prompt_confirm "Desea cerrar el puerto 22 (puerto por defecto)?" "Y"; then
                ufw delete allow 22/tcp
                log "INFO" "Regla para puerto 22 eliminada."
            fi
        fi

        if prompt_confirm "Desea habilitar el firewall ahora? (Asegúrese de tener acceso)" "Y"; then
            echo "y" | ufw enable
            log "SUCCESS" "Firewall habilitado."
        fi
    fi
}

# Verificación y reinicio
finalize_changes() {
    log "INFO" "Verificando la nueva configuración..."
    
    # Validar sintaxis usando el archivo temporal
    if sshd -t -f "${SSHD_CONFIG}.temp"; then
        log "SUCCESS" "La sintaxis del archivo de configuración es correcta."
        
        if prompt_confirm "Desea aplicar los cambios y reiniciar el servicio SSH?" "Y"; then
            mv "${SSHD_CONFIG}.temp" "$SSHD_CONFIG"
            systemctl restart sshd
            log "SUCCESS" "Servicio SSH reiniciado."
            
            echo -e "${YELLOW}======================================================${NC}"
            echo -e "${YELLOW} ATENCIÓN: NO CIERRE ESTA SESIÓN AÚN${NC}"
            echo -e "Abra una NUEVA terminal e intente conectarse con:"
            echo -e "${GREEN}ssh -p $SSH_PORT $TARGET_USER@<IP-DEL-SERVIDOR>${NC}"
            echo -e "${YELLOW}======================================================${NC}"
            
            if prompt_confirm "Ha verificado que puede conectarse en una nueva sesión?" "N"; then
                log "SUCCESS" "Configuración completada exitosamente."
            else
                log "WARN" "Restaurando configuración original por seguridad..."
                cp "$BACKUP_DIR/sshd_config.backup.$(ls -t "$BACKUP_DIR" | head -n1 | cut -d'.' -f3)" "$SSHD_CONFIG"
                systemctl restart sshd
                log "INFO" "Configuración restaurada."
            fi
        fi
    else
        log "ERROR" "La configuración generada tiene errores de sintaxis. No se aplicarán cambios."
        rm "${SSHD_CONFIG}.temp"
    fi
}

# Main
main() {
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   SCRIPT DE SECURIZACIÓN SSH INTERACTIVO   ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    check_root
    
    log "INFO" "Iniciando proceso de configuración..."
    backup_config
    
    configure_port
    create_user
    setup_keys
    harden_sshd
    configure_firewall
    finalize_changes
    
    log "SUCCESS" "Script finalizado."
}

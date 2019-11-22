#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
set -x

mkdir -p /tmp/logs
mkdir -p /etc/consul.d


# Function used for initialize Consul. Requires 2 arguments: Log level and the hostname assigned by the respective variables.
# If no log level is specified in the main.tf, then default "info" is used.
init_consul () {
    killall consul

    LOG_LEVEL=$1
    if [ -z "$1" ]; then
        LOG_LEVEL="info"
    fi

    if [ -d /tmp/logs ]; then
    mkdir /tmp/logs
    LOG="/tmp/logs/$2.log"
    else
    LOG="consul.log"
    fi

    sudo useradd --system --home /etc/consul.d --shell /bin/false consul
    sudo chown --recursive consul:consul /etc/consul.d
    sudo chmod -R 755 /etc/consul.d/
    sudo mkdir --parents /tmp/consul
    sudo chown --recursive consul:consul /tmp/consul
    mkdir -p /tmp/consul_logs/
    sudo chown --recursive consul:consul /tmp/consul_logs/

    cat << EOF > /etc/systemd/system/consul.service
    [Unit]
    Description="HashiCorp Consul - A service mesh solution"
    Documentation=https://www.consul.io/
    Requires=network-online.target
    After=network-online.target

    [Service]
    User=consul
    Group=consul
    ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
    ExecReload=/usr/local/bin/consul reload
    KillMode=process
    Restart=on-failure
    LimitNOFILE=65536


    [Install]
    WantedBy=multi-user.target

EOF
}

# Function that creates the conf file for the Consul servers. 

create_server_conf () {
    cat << EOF > /etc/consul.d/config_${DCNAME}.json
    
    {
        
        "server": true,
        "node_name": "${var2}",
        "bind_addr": "${IP}",
        "client_addr": "0.0.0.0",
        "bootstrap_expect": ${SERVER_COUNT},
        "retry_join_wan": ["provider=aws tag_key=join_wan tag_value=${JOIN_WAN}"],
        "retry_join": ["provider=aws tag_key=consul tag_value=${DCNAME}"],
        "log_level": "${LOG_LEVEL}",
        "data_dir": "/tmp/consul",
        "enable_script_checks": true,
        "domain": "${DOMAIN}",
        "datacenter": "${DCNAME}",
        "ui": true,
        "disable_remote_exec": true,
        "connect": {
          "enabled": true
        },
        "ports": {
            "grpc": 8502
        }

    }
EOF
}

# Function that creates the conf file for Consul clients. 
create_client_conf() {
    cat << EOF > /etc/consul.d/consul_client.json

        {
            "node_name": "${var2}",
            "bind_addr": "${IP}",
            "client_addr": "0.0.0.0",
            "retry_join": ["provider=aws tag_key=consul tag_value=${DCNAME}"],
            "log_level": "${LOG_LEVEL}",
            "data_dir": "/tmp/consul",
            "enable_script_checks": true,
            "domain": "${DOMAIN}",
            "datacenter": "${DCNAME}",
            "ui": true,
            "disable_remote_exec": true,
            "leave_on_terminate": false,
            "ports": {
                "grpc": 8502
            },
            "connect": {
                "enabled": true
            }
        }

EOF
}

# Starting consul
init_consul ${LOG_LEVEL} ${var2} 
case "${DCNAME}" in
    "${DCNAME}")
    if [[ "${var2}" =~ "ip-10-123-1" || "${var2}" =~ "ip-10-124-1" ]]; then
        killall consul

        create_server_conf

        sudo systemctl enable consul >/dev/null
    
        sudo systemctl start consul >/dev/null
        sleep 5
    else
        if [[ "${var2}" =~ "ip-10-123-2" || "${var2}" =~ "ip-10-123-2" ]]; then
            killall consul
            create_client_conf
            sudo systemctl enable consul >/dev/null
            sudo systemctl start consul >/dev/null
        fi
    fi
    ;;
esac

sleep 5
consul members
consul members -wan

set +x
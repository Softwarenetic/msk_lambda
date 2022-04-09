# glue-streaming-kafka-etl

## IoT - Kafka - Glue Streaming


# Create Kafka cluster

1. Security group `kafka-sg` and ingress rule
    - Protocol: TCP Port range: 9092
    - Protocol: TCP Port range: 9094
    - Protocol: TCP Port range: 2181
    - All traffic to `kafka-sg` security group or VPC CIDR range

2. Create Kafka (MSK) cluster on Console
    - Name: MSKWorkshopCluster
    - Apache Kafka version: 2.6.2
    - Configuration Section
      - auto.create.topics.enable - allow topics to be created automatically by producers and consumers.
      - delete.topic.enable - enables topic deletion on the server.
      - log.retention.hours - 8 hours for the lab.
    - Select VPC with 3 private subnet and which the same located with glue connector will created later
    - Select kafka.m5.large as the Broker Instance Type and 1 for the number of brokers per AZ
    - 100GiB Storage per Broker
    - Un-check Enable encryption within the cluster
    - Select Both TLS encrypted and plaintext traffic allowed.
    - Select Use AWS managed CMK.
    - Leave Enable TLS client authentication blank.
    - Select Enhanced topic-level monitoring. This let you troubleshoot and understand your traffic better.
    - Select Enable open monitoring with Prometheus
    - Broker log delivery to CloudWatch logs
    - Select Customize Settings, then in the drop down box select the `kafka-sg` security group

3. Optional, create by CLI

- Create configuration

```bash
aws kafka create-configuration --name "WorkshopMSKConfig" \
--description "Configuration used for MSK workshop - Auto topic creation; topic deletion; 8hrs retention" \
--kafka-versions "2.6.2" --server-properties file://cluster_config.txt

cluster_config.txt

 auto.create.topics.enable = true
 delete.topic.enable = true
 log.retention.hours = 8

```

- clusterinfo.json

```json
{
    "BrokerNodeGroupInfo": {
        "BrokerAZDistribution": "DEFAULT",
        "InstanceType": "kafka.m5.large",
        "ClientSubnets": [
            "subnet-09bbd8a628bc40e07", "subnet-0c9da7354a25eed7e"
        ],
        "SecurityGroups": [
            "sg-0ced57eee818d3811"
        ],
        "StorageInfo": {
            "EbsStorageInfo": {
                "VolumeSize": 100
            }
        }
    },
    "ClusterName": "MSKWorkshopCluster",
    "ConfigurationInfo": {
        "Arn": "arn:aws-cn:kafka:cn-north-1:<accont-id>:configuration/WorkshopMSKConfig/4fbefc4f-dc0b-4174-9bb7-a0b52632b712-4",
        "Revision": 1
    },
    "EncryptionInfo": {
        "EncryptionAtRest": {
            "DataVolumeKMSKeyId": ""
        },
        "EncryptionInTransit": {
            "InCluster": false,
            "ClientBroker": "TLS_PLAINTEXT"
        }
    },
    "EnhancedMonitoring": "PER_TOPIC_PER_BROKER",
    "KafkaVersion": "2.6.2",
    "NumberOfBrokerNodes": 2,
    "OpenMonitoring": {
        "Prometheus": {
            "JmxExporter": {
                "EnabledInBroker": true
            },
            "NodeExporter": {
                "EnabledInBroker": true
            }
        }
    }
}
```

- Create cluster

```bash
aws kafka create-cluster --cli-input-json file://clusterinfo.json

# copy and create vairable for ClusterArn
aws kafka describe-cluster --cluster-arn $ClusterArn | grep -i state
```

# Create the Topic and produce data

1. login to EC2 or Cloud9 IDE

2. install client and create topic

```bash
sudo yum install java-1.8.0
wget https://archive.apache.org/dist/kafka/2.2.1/kafka_2.12-2.2.1.tgz
tar -xzf kafka_2.12-2.2.1.tgz
cd kafka_2.12-2.2.1/

ZookeeperConnectString=$(aws kafka describe-cluster --cluster-arn $ClusterArn --region cn-north-1 | jq .ClusterInfo.ZookeeperConnectString | sed 's/"//g' )
echo ${ZookeeperConnectString}

# replacing ZookeeperConnectString with the value that after you ran the describe-cluster command. 
bin/kafka-topics.sh --create --zookeeper $ZookeeperConnectString --replication-factor 2 --partitions 1 --topic AWSKafkaTutorialTopic
```

3. Produce and consume data, verify the data can be produced and consumed correctly

```bash
cp /usr/lib/jvm/java-1.8.0-openjdk-1.8.0.252.b09-2.amzn2.0.1.x86_64/jre/lib/security/cacerts /tmp/kafka.client.truststore.jks
# create client.properties
cat kafka_2.12-2.2.1/config/client.properties
security.protocol=SSL
ssl.truststore.location=/tmp/kafka.client.truststore.jks

BootstrapBrokerString=$(aws kafka get-bootstrap-brokers --region cn-north-1 --cluster-arn $ClusterArn | jq .BootstrapBrokerString | sed 's/"//g' )
echo ${BootstrapBrokerString}

BootstrapBrokerStringTls=$(aws kafka get-bootstrap-brokers --region cn-north-1 --cluster-arn $ClusterArn | jq .BootstrapBrokerStringTls | sed 's/"//g' )
echo ${BootstrapBrokerStringTls}

# Producer
cd kafka_2.12-2.2.1/
bin/kafka-console-producer.sh --broker-list $BootstrapBrokerStringTLS --producer.config config/client.properties --topic AWSKafkaTutorialTopic
OR
bin/kafka-console-producer.sh --broker-list $BootstrapBrokerString --topic AWSKafkaTutorialTopic

# Consumer
bin/kafka-console-consumer.sh --bootstrap-server $BootstrapBrokerStringTLS --consumer.config config/client.properties --topic AWSKafkaTutorialTopic --from-beginning
OR
bin/kafka-console-consumer.sh --bootstrap-server $BootstrapBrokerString --topic AWSKafkaTutorialTopic --from-beginning
```

4. Python producer code

```bash
# Install dependency
pip install -r scripts/requirements.txt

# Run code to send, once per second, a JSON message with sensor data to the `AWSKafkaTutorialTopic` Kafka topic.
cd scripts
python scripts/iot-kafka-producer.py

# Check the consumer terminal can get the message
bin/kafka-console-consumer.sh --bootstrap-server $BootstrapBrokerStringTLS --consumer.config config/client.properties --topic AWSKafkaTutorialTopic --from-beginning
```

# Processing Streaming Data with AWS Glue

1. Create Kafka connection for AWS Glue

- Click “Add connection”, input the Connection Name as `kafkatest`, Connection type for Kafka, Kafka bootstrap server URLs you get it from Kafka cluster `$BootstrapBrokerStringTLS`
- Connection for Kafka by default use the SSL connection, you CAN NOT use the Kafka bootstrap server URLs without TLS

  ![iot2kafka-connection](media/iot2kafka-connection.png)

- Choose the VPC, Subnet and security group. The security group need open all ingress ports for same security group or VPC CIDR range

  Otherwise the Glue job will failed with error

  ```bash
  JobName:kafka-streaming and JobRunId:jr_1dc5fbc66da7 failed to execute with exception At least one security group must open all ingress ports.
  To limit traffic, the source security group in your inbound rule can be restricted to the same security group
  ```

2. I manually add a table in the Glue Data Catalog.

- Click Database and Add database, to create a new database `kafkatest`.
![iot2kafka-table1](media/iot2kafka-table1.png)
- Click Tables and Add tables, to add a new table `kafkatest` from Kafka connection with topic `AWSKafkaTutorialTopic`
![iot2kafka-table2](media/iot2kafka-table2.png)
- Format: json
- Table schema

```json
kafkatest = {
            "client_id": string
            "timestamp": timestamp,
            "humidity": int,
            "temperature": int,
            "pressure": int,
            "pitch": string,
            "roll": string,
            "yaw": string,
            "count": bigint
        }
```

3. Create Glue Streaming ETL job.

    Create a new job to ingest data from Kafka, and store the data into S3.

- The IAM role with `AWSGlueServiceRole` and `AmazonMSKReadOnlyAccess` managed policies.
- Create Glue Streaming job with name `kafka-streaming`
  - Select the type as `Spark Streaming` and Glue version `Spark2.4, Python 3`
 ![iot2kafka-job1](media/iot2kafka-job1.png)
  - For the data source, select the table `kafkatest` as just created, receiving data from the Kafka stream.
 ![iot2kafka-job2](media/iot2kafka-job2.png)
  - As target, create a new table in the Glue Data Catalog, using `JSON` format. The JSON files generated by this job are going to be stored in an S3 bucket
 ![iot2kafka-job3](media/iot2kafka-job3.png)
  - Leave the default mapping that keeps in output all the columns in the source stream.
 ![iot2kafka-job4](media/iot2kafka-job4.png)
  - Click Save job and edit scripts, you will see the scripts generated automatically. You can add your processing logic, or update the currently code. If you update the code, please click Save.
 ![iot2kafka-job5](media/iot2kafka-job5.png)
- Start the job, and after a few minutes, you can see the checkpoint information and the ingested data partitioned. They are partitioned by ingest date (year, month, day, and hour).
 ![iot2kafka-S3](media/iot2kafka-S3.png)
- Check the cloudwatch logs

You will see the job history from below, and you can click the “Logs” or “Error logs” to see the detailed information.

SSL/TLS connection

```bash
consumer.ConsumerConfig (AbstractConfig.java:logAll(180)) - ConsumerConfig values: 
 auto.commit.interval.ms = 5000
 auto.offset.reset = earliest
 bootstrap.servers = [b-1.amazonaws.com:9094, b-2.amazonaws.com:9094]
 check.crcs = true
 client.id = 
 connections.max.idle.ms = 540000
 enable.auto.commit = false
 exclude.internal.topics = true
 fetch.max.bytes = 52428800
 fetch.max.wait.ms = 500
 fetch.min.bytes = 1
 group.id = spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0
 heartbeat.interval.ms = 3000
 interceptor.classes = null
 key.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
 max.partition.fetch.bytes = 1048576
 max.poll.interval.ms = 300000
 max.poll.records = 1
 metadata.max.age.ms = 300000
 metric.reporters = []
 metrics.num.samples = 2
 metrics.sample.window.ms = 30000
 partition.assignment.strategy = [class org.apache.kafka.clients.consumer.RangeAssignor]
 receive.buffer.bytes = 65536
 reconnect.backoff.ms = 50
 request.timeout.ms = 305000
 retry.backoff.ms = 100
 sasl.kerberos.kinit.cmd = /usr/bin/kinit
 sasl.kerberos.min.time.before.relogin = 60000
 sasl.kerberos.service.name = null
 sasl.kerberos.ticket.renew.jitter = 0.05
 sasl.kerberos.ticket.renew.window.factor = 0.8
 sasl.mechanism = GSSAPI
 security.protocol = SSL
 send.buffer.bytes = 131072
 session.timeout.ms = 10000
 ssl.cipher.suites = null
 ssl.enabled.protocols = [TLSv1.2, TLSv1.1, TLSv1]
 ssl.endpoint.identification.algorithm = null
 ssl.key.password = null
 ssl.keymanager.algorithm = SunX509
 ssl.keystore.location = null
 ssl.keystore.password = null
 ssl.keystore.type = JKS
 ssl.protocol = TLS
 ssl.provider = null
 ssl.secure.random.implementation = null
 ssl.trustmanager.algorithm = PKIX
 ssl.truststore.location = ExternalAndAWSTrustStore.jks
 ssl.truststore.password = [hidden]
 ssl.truststore.type = JKS
 value.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
 
2020-06-01 01:32:54,819 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] utils.AppInfoParser (AppInfoParser.java:<init>(83)) - Kafka version : 0.10.1.0
2020-06-01 01:32:54,819 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] utils.AppInfoParser (AppInfoParser.java:<init>(84)) - Kafka commitId : 3402a74efb23d1d4
2020-06-01 01:32:55,042 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] internals.AbstractCoordinator (AbstractCoordinator.java:onSuccess(555)) - Discovered coordinator b-1.mskworkshopcluster.8bx5lx.c4.kafka.cn-north-1.amazonaws.com.cn:9094 (id: 2147483646 rack: null) for group spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0.
2020-06-01 01:32:55,045 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] internals.ConsumerCoordinator (ConsumerCoordinator.java:onJoinPrepare(333)) - Revoking previously assigned partitions [] for group spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0
2020-06-01 01:32:55,045 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] internals.AbstractCoordinator (AbstractCoordinator.java:sendJoinGroupRequest(381)) - (Re-)joining group spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0
2020-06-01 01:32:58,163 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] internals.AbstractCoordinator (AbstractCoordinator.java:onSuccess(349)) - Successfully joined group spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0 with generation 1
2020-06-01 01:32:58,165 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] internals.ConsumerCoordinator (ConsumerCoordinator.java:onJoinComplete(225)) - Setting newly assigned partitions [AWSKafkaTutorialTopic-0] for group spark-kafka-source-f2d72bad-0e10-4898-949f-fdb6d55e5b49--367204582-driver-0
2020-06-01 01:32:58,427 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] Configuration.deprecation (Configuration.java:logDeprecation(1285)) - io.bytes.per.checksum is deprecated. Instead, use dfs.bytes-per-checksum
2020-06-01 01:32:58,488 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] streaming.CheckpointFileManager (Logging.scala:logInfo(54)) - Writing atomically to s3://ray-glue-streaming/checkpoint/sources/0/0 using temp file s3://ray-glue-streaming/checkpoint/sources/0/.0.b2500a85-0299-433a-b27b-f063be1c99db.tmp
2020-06-01 01:32:58,488 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] s3n.MultipartUploadOutputStream (MultipartUploadOutputStream.java:close(414)) - close closed:false s3://ray-glue-streaming/checkpoint/sources/0/.0.b2500a85-0299-433a-b27b-f063be1c99db.tmp
2020-06-01 01:32:58,617 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] s3n.S3NativeFileSystem (S3NativeFileSystem.java:rename(1233)) - rename s3://ray-glue-streaming/checkpoint/sources/0/.0.b2500a85-0299-433a-b27b-f063be1c99db.tmp s3://ray-glue-streaming/checkpoint/sources/0/0
2020-06-01 01:32:58,718 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] streaming.CheckpointFileManager (Logging.scala:logInfo(54)) - Renamed temp file s3://ray-glue-streaming/checkpoint/sources/0/.0.b2500a85-0299-433a-b27b-f063be1c99db.tmp to s3://ray-glue-streaming/checkpoint/sources/0/0
2020-06-01 01:32:58,718 INFO  [stream execution thread for [id = ca3e241b-607b-4c02-9d9f-ec8c2683acc5, runId = 8015748b-4851-4e06-aaf0-0035ae612d5c]] kafka010.KafkaMicroBatchReader (Logging.scala:logInfo(54)) - Initial offsets: 
{
    "AWSKafkaTutorialTopic": {
        "0": 0
    }
}
 
```
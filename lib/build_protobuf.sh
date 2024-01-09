# download from https://github.com/protocolbuffers/protobuf/releases/tag/v25.1
# put bin into /usr/local/bin
# put include into /usr/local/include
# run dart pub global activate protoc_plugin
protoc -I=. --dart_out=. ./message.proto
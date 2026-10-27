import 'dart:io';

class ServiceAuthException extends HttpException {
  final int status;
  ServiceAuthException(String message, this.status) : super(message);
}

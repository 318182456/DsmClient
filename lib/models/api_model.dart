// @dart=2.10
/// maxVersion : 6
/// minVersion : 1
/// path : "auth.cgi"

class ApiModel {
  ApiModel({
    this.maxVersion,
    this.minVersion,
    this.path,
  });
  ApiModel.fromJson(dynamic json) {
    maxVersion = num.tryParse('${json['maxVersion']}') ?? 1;
    minVersion = num.tryParse('${json['minVersion']}') ?? 1;
    path = json['path'];
  }
  num maxVersion;
  num minVersion;
  String path;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['maxVersion'] = maxVersion;
    map['minVersion'] = minVersion;
    map['path'] = path;
    return map;
  }
}

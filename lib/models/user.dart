import 'package:vekolo/models/rekord.dart';

class User with RekordMixin {
  User.fromData(Map<String, Object?> data) : rekord = Rekord(data);

  factory User.create({String? id, String? name, String? email, int? ftp, int? weight}) {
    return User.fromData({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (ftp != null) 'ftp': ftp,
      if (weight != null) 'weight': weight,
    });
  }

  @override
  final Rekord rekord;
  static final init = UserInit();

  String get id => rekord.read('id').asStringOrThrow();
  String get name => rekord.read('name').asStringOrThrow();
  String get email => rekord.read('email').asStringOrThrow();
  int get ftp => rekord.read('ftp').asIntOrThrow();
  int get weight => rekord.read('weight').asIntOrThrow();

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email, 'ftp': ftp, 'weight': weight};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'User(id: $id, name: $name, email: $email)';
}

class UserInit {}

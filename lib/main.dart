import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Maa Nachinda Filling Station',
    home: LoginScreen(),
  ));
}

Map<String, String> getShiftInfo(DateTime now) {
  int h = now.hour;
  DateTime d = now;
  String s = "Shift 3 (10 PM - 6 AM)";
  if (h >= 6 && h < 14) {
    s = "Shift 1 (6 AM - 2 PM)";
  } else if (h >= 14 && h < 22) {
    s = "Shift 2 (2 PM - 10 PM)";
  } else if (h < 6) {
    d = now.subtract(const Duration(days: 1));
  }
  return {"shift": s, "date": DateFormat('yyyy-MM-dd').format(d)};
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();

  void _login() async {
    String p = _phone.text.trim();
    if (p == "9999999999") {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
      return;
    }
    var q = await FirebaseFirestore.instance.collection('users').where('phone', isEqualTo: p).get();
    if (q.docs.isNotEmpty && mounted) {
      var u = q.docs.first.data();
      u['id'] = q.docs.first.id;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StaffScreen(user: u)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("নম্বরটি রেজিস্টার করা নেই!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_gas_station, size: 70, color: Colors.indigo),
            const SizedBox(height: 10),
            const Text("MAA NACHINDA FILLING STATION", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "মোবাইল নম্বর", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            ElevatedButton(onPressed: _login, child: const Text("লগইন করুন")),
            const SizedBox(height: 10),
            const Text("অ্যাডমিন লগইন: 9999999999", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class StaffScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const StaffScreen({super.key, required this.user});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  String? activeDocId;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _checkActive();
  }

  void _checkActive() async {
    var q = await FirebaseFirestore.instance.collection('attendance')
        .where('user_id', isEqualTo: widget.user['id']).where('status', isEqualTo: 'Active').get();
    if (q.docs.isNotEmpty) setState(() => activeDocId = q.docs.first.id);
  }

  void _punchIn() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, imageQuality: 25, maxWidth: 400);
    if (photo == null) return;
    setState(() => loading = true);
    try {
      await Geolocator.requestPermission();
      Position pos = await Geolocator.getCurrentPosition();
      var pump = await FirebaseFirestore.instance.collection('pumps').doc(widget.user['pump_id']).get();
      double dist = Geolocator.distanceBetween(pump['lat'], pump['lng'], pos.latitude, pos.longitude);
      if (dist > 100) throw "আপনি পাম্পের ১০০ মিটারের বাইরে আছেন!";

      String base64Img = base64Encode(await File(photo.path).readAsBytes());
      DateTime now = DateTime.now();
      var sInfo = getShiftInfo(now);

      await FirebaseFirestore.instance.collection('attendance').add({
        'user_id': widget.user['id'],
        'user_name': widget.user['name'],
        'pump_name': widget.user['pump_name'],
        'shift': sInfo['shift'],
        'shift_date': sInfo['date'],
        'in_time': Timestamp.fromDate(now),
        'out_time': null,
        'selfie': base64Img,
        'status': 'Active',
      });
      _checkActive();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
    setState(() => loading = false);
  }

  void _punchOut() async {
    setState(() => loading = true);
    await FirebaseFirestore.instance.collection('attendance').doc(activeDocId).update({
      'out_time': Timestamp.fromDate(DateTime.now()),
      'status': 'Completed',
    });
    setState(() { activeDocId = null; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    var sInfo = getShiftInfo(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(widget.user['name'])),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("পাম্প: ${widget.user['pump_name']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("শিফট: ${sInfo['shift']}"),
            const SizedBox(height: 30),
            loading ? const CircularProgressIndicator() : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: activeDocId == null ? Colors.green : Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(20)),
              onPressed: activeDocId == null ? _punchIn : _punchOut,
              child: Text(activeDocId == null ? "সেলফি তুলে CHECK-IN করুন" : "CHECK-OUT করুন", style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  void _addPump(BuildContext context) {
    final n = TextEditingController(), lat = TextEditingController(), lng = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("নতুন পাম্প যোগ করুন"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: "পাম্পের নাম")),
        TextField(controller: lat, decoration: const InputDecoration(labelText: "Latitude (যেমন: 21.9012)")),
        TextField(controller: lng, decoration: const InputDecoration(labelText: "Longitude (যেমন: 87.5345)")),
      ]),
      actions: [TextButton(onPressed: () async {
        await FirebaseFirestore.instance.collection('pumps').add({'name': n.text, 'lat': double.parse(lat.text), 'lng': double.parse(lng.text)});
        if (context.mounted) Navigator.pop(context);
      }, child: const Text("সেভ"))],
    ));
  }

  void _addStaff(BuildContext context) async {
    final n = TextEditingController(), p = TextEditingController(), w = TextEditingController();
    var pumps = await FirebaseFirestore.instance.collection('pumps').get();
    if (pumps.docs.isEmpty) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("নতুন স্টাফ যোগ করুন"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: "স্টাফের নাম")),
        TextField(controller: p, decoration: const InputDecoration(labelText: "মোবাইল নম্বর")),
        TextField(controller: w, decoration: const InputDecoration(labelText: "শিফট বেতন (টাকা)")),
      ]),
      actions: [TextButton(onPressed: () async {
        await FirebaseFirestore.instance.collection('users').add({
          'name': n.text, 'phone': p.text.trim(), 'wage': double.parse(w.text),
          'pump_id': pumps.docs.first.id, 'pump_name': pumps.docs.first['name'],
        });
        if (context.mounted) Navigator.pop(context);
      }, child: const Text("সেভ"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    String curMonth = DateFormat('yyyy-MM').format(DateTime.now());
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin - Maa Nachinda"),
          bottom: const TabBar(tabs: [Tab(text: "হাজিরা"), Tab(text: "পাম্প/স্টাফ"), Tab(text: "পেরোল")]),
        ),
        body: TabBarView(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('attendance').orderBy('in_time', descending: true).snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.builder(
                  itemCount: s.data!.docs.length,
                  itemBuilder: (c, i) {
                    var d = s.data!.docs[i];
                    return ListTile(
                      leading: CircleAvatar(backgroundImage: MemoryImage(base64Decode(d['selfie']))),
                      title: Text("${d['user_name']} (${d['shift']})"),
                      subtitle: Text("তারিখ: ${d['shift_date']} | ${d['status']}"),
                    );
                  },
                );
              },
            ),
            Column(children: [
              const SizedBox(height: 15),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ElevatedButton(onPressed: () => _addPump(context), child: const Text("+ পাম্প যোগ")),
                ElevatedButton(onPressed: () => _addStaff(context), child: const Text("+ স্টাফ যোগ")),
              ]),
              Expanded(child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (c, s) {
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView.builder(itemCount: s.data!.docs.length, itemBuilder: (c, i) {
                    var u = s.data!.docs[i];
                    return ListTile(title: Text(u['name']), subtitle: Text("ফোন: ${u['phone']} | ₹${u['wage']}/শিফট"));
                  });
                },
              ))
            ]),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.builder(itemCount: s.data!.docs.length, itemBuilder: (c, i) {
                  var u = s.data!.docs[i];
                  return FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('attendance').where('user_id', isEqualTo: u.id).where('status', isEqualTo: 'Completed').get(),
                    builder: (c, att) {
                      if (!att.hasData) return ListTile(title: Text(u['name']));
                      int shifts = att.data!.docs.where((doc) => doc['shift_date'].toString().startsWith(curMonth)).length;
                      double totalPay = shifts * (u['wage'] as num).toDouble();
                      return ListTile(
                        title: Text(u['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("মাস: $curMonth | মোট শিফট: $shifts টি"),
                        trailing: Text("₹$totalPay", style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                      );
                    },
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

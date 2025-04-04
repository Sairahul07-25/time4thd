import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const CalendarScreen(),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  CalendarScreenState createState() => CalendarScreenState();
}

class CalendarScreenState extends State<CalendarScreen> {
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notes Calendar")),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotePage(date: selectedDay),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class NotePage extends StatefulWidget {
  final DateTime date;
  const NotePage({super.key, required this.date});

  @override
  NotePageState createState() => NotePageState();
}

class NotePageState extends State<NotePage> {
  final TextEditingController _controller = TextEditingController();
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isRecording = false;
  bool _isPlaying = false;
  List<Map<String, String>> _voiceNotes = [];
  final uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _init();
  }

  Future<void> _init() async {
    await _recorder!.openRecorder();
    await _player!.openPlayer();
    await _loadNotes();
  }

  Future<void> _loadNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _controller.text = prefs.getString(_getTextKey()) ?? '';
    final voiceJson = prefs.getString(_getVoiceKey());
    if (voiceJson != null) {
      _voiceNotes = List<Map<String, String>>.from(json.decode(voiceJson));
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveTextNote() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getTextKey(), _controller.text);
  }

  Future<void> _saveVoiceNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getVoiceKey(), json.encode(_voiceNotes));
  }

  Future<void> _startRecording() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) return;

    final dir = await getApplicationDocumentsDirectory();
    final id = uuid.v4();
    final path = '${dir.path}/note_${widget.date.toIso8601String()}_$id.aac';

    await _recorder!.startRecorder(toFile: path, codec: Codec.aacADTS);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder!.stopRecorder();
    final name = 'Recording ${_voiceNotes.length + 1}';

    _voiceNotes.add({"path": path!, "name": name});
    await _saveVoiceNotes();

    setState(() => _isRecording = false);
  }

  Future<void> _play(String path) async {
    if (!File(path).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Voice file not found.")),
      );
      return;
    }

    try {
      await _player!.startPlayer(
        fromURI: path,
        codec: Codec.aacADTS,
        whenFinished: () {
          if (mounted) {
            setState(() => _isPlaying = false);
          }
        },
      );
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Playback failed: $e")),
        );
      }
    }
  }



  Future<void> _stop() async {
    await _player!.stopPlayer();
    setState(() => _isPlaying = false);
  }

  String _getTextKey() => "note_${widget.date.toIso8601String()}";
  String _getVoiceKey() => "voice_${widget.date.toIso8601String()}";

  void _renameDialog(int index) {
    final renameController = TextEditingController(text: _voiceNotes[index]['name']);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Recording'),
        content: TextField(controller: renameController),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text("Rename"),
            onPressed: () async {
              setState(() {
                _voiceNotes[index]['name'] = renameController.text;
              });
              await _saveVoiceNotes();
              if (mounted) Navigator.pop(context);
            },
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    _player!.closePlayer();
    _saveTextNote();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.date.toLocal().toString().split(' ')[0];

    return Scaffold(
      appBar: AppBar(title: Text("Notes for $dateStr")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(hintText: "Write your note here"),
              onChanged: (_) => _saveTextNote(),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? "Stop Recording" : "Start Voice Recording"),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _voiceNotes.length,
                itemBuilder: (context, index) {
                  final voice = _voiceNotes[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.voice_chat),
                      title: Text(voice['name'] ?? 'Voice Note'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: _isPlaying ? _stop : () => _play(voice['path']!),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _renameDialog(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

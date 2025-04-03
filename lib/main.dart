import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// 📅 Calendar Screen
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

// 📝 Note Page (Text + Voice Notes)
class NotePage extends StatefulWidget {
  final DateTime date;
  const NotePage({super.key, required this.date});

  @override
  NotePageState createState() => NotePageState();
}

class NotePageState extends State<NotePage> {
  final TextEditingController _controller = TextEditingController();
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _filePath;
  String? _savedTextNote;
  String? _savedVoicePath;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _initRecorder();
    _loadNote();
  }

  // 📌 Initialize Recorder
  Future<void> _initRecorder() async {
    await _recorder!.openRecorder();
  }

  // 🔹 Load Saved Notes from SharedPreferences
  Future<void> _loadNote() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedTextNote = prefs.getString(_getTextKey());
      _savedVoicePath = prefs.getString(_getVoiceKey());
      if (_savedTextNote != null) {
        _controller.text = _savedTextNote!;
      }
    });
  }

  // 🔹 Save Text Note to SharedPreferences
  Future<void> _saveNote() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getTextKey(), _controller.text);
  }

  // 🎤 Start Voice Recording
  Future<void> _startRecording() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!mounted) return;

    _filePath = "${directory.path}/note_${widget.date.toIso8601String()}.aac";

    await _recorder!.startRecorder(
      toFile: _filePath,
      codec: Codec.aacADTS,
    );

    if (!mounted) return;
    setState(() {
      _isRecording = true;
    });
  }

  // 🎤 Stop Voice Recording & Save File Path
  Future<void> _stopRecording() async {
    await _recorder!.stopRecorder();
    if (!mounted) return; // ✅ Ensure widget is still in the tree

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_getVoiceKey(), _filePath!);

    setState(() {
      _isRecording = false;
      _savedVoicePath = _filePath;
    });

    if (!mounted) return; // ✅ Check again before using context
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Voice note saved: $_filePath")),
    );
  }

  // 📌 Helper function to get the storage key for text notes
  String _getTextKey() {
    return "note_${widget.date.toIso8601String()}";
  }

  // 📌 Helper function to get the storage key for voice recordings
  String _getVoiceKey() {
    return "voice_${widget.date.toIso8601String()}";
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    _saveNote();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Notes for ${widget.date.toLocal()}".split(' ')[0])),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(hintText: "Write your note here"),
              onChanged: (text) => _saveNote(), // Save on text change
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
              label: Text(_isRecording ? "Stop Recording" : "Start Voice Recording"),
            ),
            const SizedBox(height: 20),
            if (_savedVoicePath != null)
              Text(
                "Voice note saved!",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}

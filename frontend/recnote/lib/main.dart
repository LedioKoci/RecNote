import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecNote',
      theme: ThemeData(
        fontFamily: 'Poppins',
        primaryColor: Color(0xFFFF7B06),
        scaffoldBackgroundColor: Color(0xFFF0F2F5),
        colorScheme: ColorScheme.light(
          primary: Color(0xFFFF7B06),
          secondary: Color(0xFF1E272E),
          background: Color(0xFFF0F2F5),
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: Colors.black,
          onSurface: Colors.black,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 70,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFFF7B06),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            elevation: 4,
            shadowColor: Color(0xFFFF7B06).withOpacity(0.3),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.symmetric(vertical: 8),
        ),
        textTheme: TextTheme(
          headlineSmall: TextStyle(
            color: Color(0xFF1E272E),
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF1E272E),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF1E272E),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF4A4A4A),
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF6C6C6C),
            fontSize: 14,
          ),
        ),
      ),
      home: RecNoteHome(),
    );
  }
}

class TranscriptionItem {
  final String id;
  final String title;
  final String transcript;
  final String summary;
  final DateTime createdAt;

  TranscriptionItem({
    required this.id,
    required this.title,
    required this.transcript,
    required this.summary,
    required this.createdAt,
  });
}

class RecNoteHome extends StatefulWidget {
  @override
  _RecNoteHomeState createState() => _RecNoteHomeState();
}

class _RecNoteHomeState extends State<RecNoteHome> with SingleTickerProviderStateMixin {
  String? _filePath;
  String _transcript = '';
  String _summary = '';
  bool _isLoading = false;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  final String _baseUrl = 'https://backend-render-hvmg.onrender.com/process-audio';
  
  List<TranscriptionItem> _savedTranscriptions = [];
  bool _isSidebarOpen = false;
  TranscriptionItem? _selectedTranscription;

  late AnimationController _sidebarAnimationController;
  late Animation<Offset> _sidebarOffsetAnimation;

  StreamSubscription? _playerSubscription;
  double _playbackPosition = 0;
  double _playbackDuration = 0;

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
    _sidebarAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _sidebarOffsetAnimation = Tween<Offset>(
      begin: Offset(-1, 0),
      end: Offset(0, 0),
    ).animate(CurvedAnimation(
      parent: _sidebarAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  

  Future<void> _initializeRecorder() async {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();

    try {
      await _recorder!.openRecorder();
      await _player!.openPlayer();

      _playerSubscription?.cancel();
      _playerSubscription = _player!.onProgress!.listen((e) {
        if (e != null && mounted) {
          setState(() {
            _playbackPosition = e.position.inMilliseconds.toDouble();
            if (_playbackDuration == 0 || e.duration.inMilliseconds.toDouble() > _playbackDuration) {
              _playbackDuration = e.duration.inMilliseconds.toDouble();
            }
          });
        }
      });
    } catch (e) {
      _showError('Error initializing recorder: $e');
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _playerSubscription?.cancel();
    _sidebarAnimationController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _transcript = '';
        _summary = '';
        _selectedTranscription = null;
        _playbackPosition = 0;
        _playbackDuration = 0; 
      });
    }
  }
  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';
        
        await _recorder!.startRecorder(
          toFile: filePath,
          codec: Codec.aacADTS,
        );
        
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
          _filePath = filePath;
          _transcript = '';
          _summary = '';
          _selectedTranscription = null;
          _playbackPosition = 0;
          _playbackDuration = 0;
        });
        
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration++;
            });
          }
        });
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      _showError('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder!.stopRecorder();
      _recordingTimer?.cancel();
      
      setState(() {
        _isRecording = false;
        _filePath = path;
        _playbackPosition = 0;
        _playbackDuration = 0; 
      });
    } catch (e) {
      _showError('Error stopping recording: $e');
    }
  }


  Future<void> _playRecording() async {
    if (_filePath != null && !_isRecording) {
      try {
        await _player!.stopPlayer();

        setState(() {
          _playbackPosition = 0;
          _playbackDuration = 0;
        });

        Codec codec = Codec.aacADTS;
        if (_filePath!.toLowerCase().endsWith('.mp3')) {
          codec = Codec.mp3;
        } else if (_filePath!.toLowerCase().endsWith('.wav')) {
          codec = Codec.pcm16WAV;
        }

        await _player!.startPlayer(
          fromURI: _filePath,
          codec: codec,
          whenFinished: () {
            if (mounted) {
              setState(() {
                _playbackPosition = 0;
              });
            }
          },
        );
        print('Playback started with codec: $codec');
      } catch (e) {
        _showError('Error playing recording: $e');
      }
    }
  }

  Future<void> _stopPlaying() async {
    try {
      await _player!.stopPlayer();
      if (mounted) {
        setState(() {
          _playbackPosition = 0;
        });
      }
    } catch (e) {
      _showError('Error stopping playback: $e');
    }
  }

  Future<void> _seekAudio(double position) async {
    if (_player!.isPlaying || _player!.isPaused) {
      try {
        await _player!.seekToPlayer(Duration(milliseconds: position.round()));
        if (mounted) {
          setState(() {
            _playbackPosition = position;
          });
        }
      } catch (e) {
        _showError('Error seeking audio: $e');
      }
    }
  }

  Future<void> _processAudio() async {
    if (_filePath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl'));
      request.files.add(await http.MultipartFile.fromPath('audio', _filePath!));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      var data = json.decode(responseBody);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _transcript = data['transcript'] ?? '';
            _summary = data['summary'] ?? '';
          });
        }
      } else {
        _showError(data['error'] ?? 'Unknown error');
      }
    } catch (e) {
      _showError('Connection error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTranscription() async {
    if (_transcript.isNotEmpty && _summary.isNotEmpty) {
      final title = await _showSaveDialog(context);
      if (title != null && title.isNotEmpty) {
        final transcription = TranscriptionItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          transcript: _transcript,
          summary: _summary,
          createdAt: DateTime.now(),
        );
        
        setState(() {
          _savedTranscriptions.insert(0, transcription);
        });
        
        _showSuccess('Transcription saved successfully!');
      }
    }
  }

  Future<String?> _showSaveDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Save Transcription',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter a title for your note',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFFF7B06), width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context, controller.text);
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _loadTranscription(TranscriptionItem item) {
    setState(() {
      _selectedTranscription = item;
      _transcript = item.transcript;
      _summary = item.summary;
      _filePath = null;
      _isSidebarOpen = false;
      _sidebarAnimationController.reverse();
    });
  }

  void _deleteTranscription(TranscriptionItem item) {
    setState(() {
      _savedTranscriptions.removeWhere((t) => t.id == item.id);
      if (_selectedTranscription?.id == item.id) {
        _selectedTranscription = null;
        _transcript = '';
        _summary = '';
      }
    });
    _showSuccess('Transcription deleted successfully!');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _downloadTranscriptAsPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Transcript', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 16),
                pw.Text(_transcript, style: pw.TextStyle(fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/transcript_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(filePath);
    _showSuccess('Transcript PDF saved and opened!');
  }

  Future<void> _downloadSummaryAsPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Summary', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 16),
                pw.Text(_summary, style: pw.TextStyle(fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/summary_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(filePath);
    _showSuccess('Summary PDF saved and opened!');
  }

  Future<void> _downloadBothAsPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Transcript', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 16),
                  pw.Text(_transcript, style: pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 24),
                  pw.Text('Summary', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 16),
                  pw.Text(_summary, style: pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/combined_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(filePath);
    _showSuccess('Combined PDF saved and opened!');
  }

  Widget _buildSidebar() {
    return SlideTransition(
      position: _sidebarOffsetAnimation,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: Color(0xFF1E272E),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 15,
              offset: Offset(4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(20, 50, 20, 20),
              decoration: BoxDecoration(
                color: Color(0xFFFF7B06),
                borderRadius: BorderRadius.only(topRight: Radius.circular(20)),
                gradient: LinearGradient(
                  colors: [Color(0xFFFF7B06), Color(0xFFF9A64A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Saved Transcriptions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _savedTranscriptions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No saved transcriptions yet.\nProcess some audio to get started!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _savedTranscriptions.length,
                      itemBuilder: (context, index) {
                        final item = _savedTranscriptions[index];
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTranscription?.id == item.id
                                ? Color(0xFFFF7B06).withOpacity(0.2)
                                : Color(0xFF2C3E50),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedTranscription?.id == item.id
                                  ? Color(0xFFFF7B06)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              item.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteTranscription(item),
                            ),
                            onTap: () => _loadTranscription(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF7B06)),
            strokeWidth: 3,
          ),
          SizedBox(height: 16),
          Text(
            'Processing Audio...',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Color(0xFF1E272E),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.mic, color: Color(0xFFFF7B06), size: 28),
            SizedBox(width: 12),
            Text('RecNote', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () {
            setState(() {
              _isSidebarOpen = !_isSidebarOpen;
            });
            _isSidebarOpen
                ? _sidebarAnimationController.forward()
                : _sidebarAnimationController.reverse();
          },
        ),
        actions: [
          if (_transcript.isNotEmpty && _summary.isNotEmpty)
            IconButton(
              icon: Icon(Icons.save, color: Color(0xFFFF7B06)),
              onPressed: _saveTranscription,
              tooltip: 'Save Transcription',
            ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Audio Input Section (unchanged)
                              Card(
                                child: Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Audio Input',
                                          style: Theme.of(context).textTheme.titleLarge),
                                      SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _isRecording ? _stopRecording : _startRecording,
                                              icon: Icon(_isRecording ? Icons.stop : Icons.mic, size: 24),
                                              label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _isRecording ? Colors.redAccent : Color(0xFFFF7B06),
                                                shadowColor: _isRecording ? Colors.redAccent.withOpacity(0.4) : Color(0xFFFF7B06).withOpacity(0.4),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 16),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: _isRecording ? null : _pickFile,
                                              icon: Icon(Icons.upload_file, color: Color(0xFF1E272E)),
                                              label: Text('Upload File', style: TextStyle(color: Color(0xFF1E272E))),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: Color(0xFF1E272E), width: 2),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_isRecording) ...[
                                        SizedBox(height: 24),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.redAccent.shade100, Colors.redAccent.shade100],
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.redAccent, width: 2),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 24),
                                              SizedBox(width: 12),
                                              Text(
                                                'Recording: ${_formatDuration(_recordingDuration * 1000)}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              // Audio File Section (unchanged)
                              if (_filePath != null && !_isRecording) ...[
                                SizedBox(height: 24),
                                Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Selected Audio:', style: Theme.of(context).textTheme.titleMedium),
                                        SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.audiotrack, color: Color(0xFFFF7B06)),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _filePath!.split('/').last,
                                                style: Theme.of(context).textTheme.bodyLarge,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        Column(
                                          children: [
                                            Slider(
                                              value: _playbackPosition.clamp(0.0, _playbackDuration),
                                              min: 0.0,
                                              max: _playbackDuration > 0 ? _playbackDuration : 1.0,
                                              onChanged: _player!.isPlaying || _player!.isPaused ? _seekAudio : null,
                                              activeColor: Color(0xFFFF7B06),
                                              inactiveColor: Color(0xFFFF7B06).withOpacity(0.3),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(_formatDuration(_playbackPosition.round())),
                                                  Text(_formatDuration(_playbackDuration.round())),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: _player!.isPaused || _player!.isStopped ? _playRecording : null,
                                                icon: Icon(Icons.play_arrow),
                                                label: Text('Play'),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: _player!.isPlaying || _player!.isPaused ? _stopPlaying : null,
                                                icon: Icon(Icons.stop),
                                                label: Text('Stop'),
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(color: Color(0xFF1E272E), width: 2),
                                                  foregroundColor: Color(0xFF1E272E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 24),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: _isLoading ? null : _processAudio,
                                            child: _isLoading
                                                ? Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                        ),
                                                      ),
                                                      SizedBox(width: 12),
                                                      Text('Processing...'),
                                                    ],
                                                  )
                                                : Text('Transcribe & Summarize'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              SizedBox(height: 24),
                              if (_isLoading || _transcript.isNotEmpty || _summary.isNotEmpty) ...[
                                Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.text_snippet, color: Color(0xFFFF7B06), size: 24),
                                                SizedBox(width: 12),
                                                Text('Transcript',
                                                    style: Theme.of(context).textTheme.titleLarge),
                                              ],
                                            ),
                                            if (!_isLoading) ...[
                                              Flexible(
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    ElevatedButton.icon(
                                                      onPressed: _downloadTranscriptAsPDF,
                                                      icon: Icon(Icons.download, size: 16),
                                                      label: Text('Transcript', style: TextStyle(fontSize: 12)),
                                                      style: ElevatedButton.styleFrom(
                                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                        textStyle: TextStyle(fontSize: 12),
                                                        minimumSize: Size(0, 36),
                                                      ),
                                                    ),
                                                    SizedBox(width: 6),
                                                    ElevatedButton.icon(
                                                      onPressed: _downloadBothAsPDF,
                                                      icon: Icon(Icons.download, size: 16),
                                                      label: Text('Both', style: TextStyle(fontSize: 12)),
                                                      style: ElevatedButton.styleFrom(
                                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                        textStyle: TextStyle(fontSize: 12),
                                                        minimumSize: Size(0, 36),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        Container(
                                          padding: EdgeInsets.all(16),
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Color(0xFFF7F7F7),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Color(0xFFE0E0E0)),
                                          ),
                                          child: _isLoading
                                              ? _buildLoadingWidget()
                                              : AnimatedOpacity(
                                                  opacity: _transcript.isNotEmpty ? 1.0 : 0.0,
                                                  duration: Duration(milliseconds: 500),
                                                  child: Text(
                                                    _transcript.isNotEmpty ? _transcript : 'No transcript available',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.copyWith(color: Colors.black),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(height: 24),
                                Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.summarize, color: Color(0xFFFF7B06), size: 24),
                                                SizedBox(width: 12),
                                                Text('Summary',
                                                    style: Theme.of(context).textTheme.titleLarge),
                                              ],
                                            ),
                                            if (!_isLoading)
                                              ElevatedButton.icon(
                                                onPressed: _downloadSummaryAsPDF,
                                                icon: Icon(Icons.download, size: 16),
                                                label: Text('Summary', style: TextStyle(fontSize: 12)),
                                                style: ElevatedButton.styleFrom(
                                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                  textStyle: TextStyle(fontSize: 12),
                                                  minimumSize: Size(0, 36),
                                                ),
                                              ),
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        Container(
                                          padding: EdgeInsets.all(16),
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFF7B06).withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Color(0xFFFF7B06).withOpacity(0.3)),
                                          ),
                                          child: _isLoading
                                              ? _buildLoadingWidget()
                                              : AnimatedOpacity(
                                                  opacity: _summary.isNotEmpty ? 1.0 : 0.0,
                                                  duration: Duration(milliseconds: 500),
                                                  child: Text(
                                                    _summary.isNotEmpty ? _summary : 'No summary available',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.copyWith(color: Colors.black),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_isSidebarOpen)
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSidebarOpen = false;
                });
                _sidebarAnimationController.reverse();
              },
              child: Container(
                color: Colors.black54,
              ),
            ),
          _buildSidebar(),
        ],
      ),
    );
  }

}
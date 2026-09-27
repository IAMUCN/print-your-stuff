class PrintSettings {
  final String? pageRange;
  final int copies;
  final String colorMode; // 'COLOR' | 'BW'
  final int pagesPerSheet;
  final String orientation;
  final String imageLayout;

  PrintSettings({
    this.pageRange,
    this.copies = 1,
    this.colorMode = 'BW',
    this.pagesPerSheet = 1,
    this.orientation = 'AUTO',
    this.imageLayout = 'FIT',
  });

  factory PrintSettings.fromJson(Map<String, dynamic> json) {
    return PrintSettings(
      pageRange: json['pageRange'] as String?,
      copies: (json['copies'] as num?)?.toInt() ?? 1,
      colorMode: (json['colorMode'] as String?) ?? 'BW',
      pagesPerSheet: (json['pagesPerSheet'] as num?)?.toInt() ?? 1,
      orientation: (json['orientation'] as String?) ?? 'AUTO',
      imageLayout: (json['imageLayout'] as String?) ?? 'FIT',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageRange': pageRange,
      'copies': copies,
      'colorMode': colorMode,
      'pagesPerSheet': pagesPerSheet,
      'orientation': orientation,
      'imageLayout': imageLayout,
    };
  }

  PrintSettings copyWith({
    String? pageRange,
    int? copies,
    String? colorMode,
    int? pagesPerSheet,
    String? orientation,
    String? imageLayout,
  }) {
    return PrintSettings(
      pageRange: pageRange ?? this.pageRange,
      copies: copies ?? this.copies,
      colorMode: colorMode ?? this.colorMode,
      pagesPerSheet: pagesPerSheet ?? this.pagesPerSheet,
      orientation: orientation ?? this.orientation,
      imageLayout: imageLayout ?? this.imageLayout,
    );
  }
}

class JobFile {
  final String id;
  final String filename;
  final String inputType; // 'PDF' | 'IMAGE' | 'DOC' | 'DOCX'
  final int? pageCount;
  final int sizeBytes;
  final PrintSettings settings;

  JobFile({
    required this.id,
    required this.filename,
    required this.inputType,
    this.pageCount,
    required this.sizeBytes,
    required this.settings,
  });

  factory JobFile.fromJson(Map<String, dynamic> json) {
    return JobFile(
      id: json['id'] as String,
      filename: (json['filename'] ?? json['originalFilename'] ?? 'document') as String,
      inputType: (json['inputType'] as String?) ?? 'PDF',
      pageCount: (json['pageCount'] as num?)?.toInt(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      settings: json['settings'] != null
          ? PrintSettings.fromJson(json['settings'] as Map<String, dynamic>)
          : PrintSettings(),
    );
  }
}

class PrintJob {
  final String id;
  final int? jobCode;
  final String studentName;
  final String status; // 'WAITING' | 'PRINTING' | 'PRINTED' | 'FAILED' | 'CANCELLED'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final int fileCount;
  final int totalSheetsEst;
  final List<JobFile> files;

  PrintJob({
    required this.id,
    this.jobCode,
    required this.studentName,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    required this.fileCount,
    required this.totalSheetsEst,
    required this.files,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List<dynamic>? ?? [];
    return PrintJob(
      id: json['id'] as String,
      jobCode: (json['jobCode'] as num?)?.toInt(),
      studentName: (json['studentName'] as String?) ?? 'Student',
      status: (json['status'] as String?) ?? 'WAITING',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'].toString()) : null,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? rawFiles.length,
      totalSheetsEst: (json['totalSheetsEst'] as num?)?.toInt() ?? 0,
      files: rawFiles.map((f) => JobFile.fromJson(f as Map<String, dynamic>)).toList(),
    );
  }
}

// Om Sai Ram
// Static audio data.
// Source URLs: GitHub Release assets (Vinnu-11/OmSaiRam, tag v1-audio).
// Original content © Shree Saibaba Sansthan Trust, Shirdi.

const String _ghBase =
    'https://github.com/Vinnu-11/OmSaiRam/releases/download/v1-audio/';

class AudioTrack {
  final String title;
  final String fileName; // local filename = GitHub release asset name
  final String? sourceUrl; // original sai.org.in URL (kept for reference)

  const AudioTrack({required this.title, required this.fileName, this.sourceUrl});

  String get downloadUrl => _ghBase + fileName;
}

class AartiGroup {
  final String name;
  final String time;
  final List<AudioTrack> tracks;

  const AartiGroup({required this.name, required this.time, required this.tracks});
}

class SatcharitaLanguage {
  final String name;
  final String displayName;
  final List<AudioTrack> chapters;

  const SatcharitaLanguage({
    required this.name,
    required this.displayName,
    required this.chapters,
  });
}

// ---------------------------------------------------------------------------
// Aarti — 5 daily aartis at Shirdi
// ---------------------------------------------------------------------------

const List<AartiGroup> kAartis = [
  AartiGroup(
    name: 'Bhupali Aarti',
    time: '5:00 AM',
    tracks: [
      AudioTrack(title: 'Utha Utha Sakaljan', fileName: 'bhupali_01_utha_utha.mp3'),
      AudioTrack(title: 'Ghanshyam Sundara', fileName: 'bhupali_02_ghanshyam.mp3'),
      AudioTrack(title: 'Om Jay Jagadish Hare', fileName: 'bhupali_03_om_jai_jagdish.mp3'),
    ],
  ),
  AartiGroup(
    name: 'Kakad Aarti',
    time: '5:15 AM',
    tracks: [
      AudioTrack(title: 'Jodoniya Kar', fileName: 'kakad_01_joduniya.mp3'),
      AudioTrack(title: 'Utha Panduranga', fileName: 'kakad_02_utha_panduranga.mp3'),
      AudioTrack(title: 'Utha Utha Shri Sainath Guru', fileName: 'kakad_03_utha_sainath.mp3'),
      AudioTrack(title: 'Darshan Dya', fileName: 'kakad_04_darshan_dya.mp3'),
      AudioTrack(title: 'Pancharati', fileName: 'kakad_05_pancharati.mp3'),
      AudioTrack(title: 'Chinmayarupa', fileName: 'kakad_06_chinmayarupa.mp3'),
      AudioTrack(title: 'Pandharinatha', fileName: 'kakad_07_pandharinatha.mp3'),
      AudioTrack(title: 'Utha Utha (Pada)', fileName: 'kakad_08_utha_pada.mp3'),
      AudioTrack(title: 'Shri Sainath Prabhatashtaka', fileName: 'kakad_09_prabhatashtaka.mp3'),
      AudioTrack(title: 'Sai Raham Najar Karna', fileName: 'kakad_10_raham_najar.mp3'),
      AudioTrack(title: 'Raham Najar Karo', fileName: 'kakad_11_raham_najar2.mp3'),
      AudioTrack(title: 'Jani Pada', fileName: 'kakad_12_jani_pada.mp3'),
      AudioTrack(title: 'Shri Sadguru Pada', fileName: 'kakad_13_sadguru_pada.mp3'),
    ],
  ),
  AartiGroup(
    name: 'Madhyan Aarti',
    time: '12:00 PM',
    tracks: [
      AudioTrack(title: 'Pancharati', fileName: 'madhyan_01_pancharati.mp3'),
      AudioTrack(title: 'Aarti Saibaba', fileName: 'madhyan_02_aarti_saibaba.mp3'),
      AudioTrack(title: 'Jay Dev Jay Dev', fileName: 'madhyan_03_jay_dev.mp3'),
      AudioTrack(title: 'Shirdi Maze Pandharpur', fileName: 'madhyan_04_shirdi_maze.mp3'),
      AudioTrack(title: 'Ghalin Lotangan', fileName: 'madhyan_05_ghalin_lotangan.mp3'),
      AudioTrack(title: 'Pushpanjali', fileName: 'madhyan_06_pushpanjali.mp3'),
      AudioTrack(title: 'Namaskarashtaka', fileName: 'madhyan_07_namaskarashtaka.mp3'),
      AudioTrack(title: 'Aisa Yei Ba', fileName: 'madhyan_08_aisa_yei_ba.mp3'),
      AudioTrack(title: 'Shri Sainath Mahimna Stotrama', fileName: 'madhyan_09_mahimna_stotrama.mp3'),
      AudioTrack(title: 'Prarthana', fileName: 'madhyan_10_prarthana.mp3'),
    ],
  ),
  AartiGroup(
    name: 'Dhup Aarti',
    time: 'Sunset',
    tracks: [
      AudioTrack(title: 'Aarti Saibaba', fileName: 'dhup_01_aarti_saibaba.mp3'),
      AudioTrack(title: 'Shirdi Maze Pandharpur', fileName: 'dhup_02_shirdi_maze.mp3'),
      AudioTrack(title: 'Ghalin Lotangan', fileName: 'dhup_03_ghalin_lotangan.mp3'),
      AudioTrack(title: 'Namaskarashtaka', fileName: 'dhup_04_namaskarashtaka.mp3'),
      AudioTrack(title: 'Aisa Yei Ba', fileName: 'dhup_05_aisa_yei_ba.mp3'),
      AudioTrack(title: 'Shri Sainath Mahimna Stotrama', fileName: 'dhup_06_mahimna.mp3'),
      AudioTrack(title: 'Shri Guruprasad Yachana', fileName: 'dhup_07_guruprasad.mp3'),
      AudioTrack(title: 'Pushapanjali', fileName: 'dhup_08_pushapanjali.mp3'),
      AudioTrack(title: 'Prarthana', fileName: 'dhup_09_prarthana.mp3'),
    ],
  ),
  AartiGroup(
    name: 'Shej Aarti',
    time: '10:00 PM',
    tracks: [
      AudioTrack(title: 'Pachahi Tatavanchi Aarti', fileName: 'shej_01_pachahi.mp3'),
      AudioTrack(title: 'Aarti Dnyanrayachi', fileName: 'shej_02_dnyanrayachi.mp3'),
      AudioTrack(title: 'Aarti Tukaramachi', fileName: 'shej_03_tukaramachi.mp3'),
      AudioTrack(title: 'Jay Jay Sainath', fileName: 'shej_04_jay_sainath.mp3'),
      AudioTrack(title: 'Aata Swami Sukhe', fileName: 'shej_05_aata_swami.mp3'),
      AudioTrack(title: 'Prasad Milnyakarita', fileName: 'shej_06_prasad_milnya.mp3'),
      AudioTrack(title: 'Prasad Milalyanantar', fileName: 'shej_07_prasad_milalyanantar.mp3'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Language-code → SatcharitaLanguage lookup map
// ---------------------------------------------------------------------------

/// Maps reader language codes to their audio language entry (if any).
const Map<String, String> _langCodeToName = {
  'mr': 'Marathi',
  'hi': 'Hindi',
  'te': 'Telugu',
  'ta': 'Tamil',
};

/// Returns the [AudioTrack] for a given reader language code and 1-based
/// chapter number, or null if no audio exists for that combination.
AudioTrack? audioTrackForChapter(String langCode, int chapterNumber) {
  final name = _langCodeToName[langCode];
  if (name == null) return null;
  final lang = kSatcharitaAudio.firstWhere(
    (l) => l.name == name,
    orElse: () => const SatcharitaLanguage(name: '', displayName: '', chapters: []),
  );
  if (lang.chapters.isEmpty) return null;

  // File names are like `te_ch01.mp3`, `hi_ch16_17.mp3`, `te_upodghatam.mp3`.
  // We scan all tracks and pick the first whose fileName covers chapterNumber.
  for (final track in lang.chapters) {
    if (_trackCoversChapter(track.fileName, chapterNumber)) return track;
  }
  return null;
}

/// Returns true if [fileName] covers [chapterNumber].
/// Handles: `te_ch01.mp3` (single), `hi_ch16_17.mp3` (range).
bool _trackCoversChapter(String fileName, int chapterNumber) {
  // Strip prefix/extension: "te_ch16_17.mp3" → "ch16_17"
  final bare = fileName.replaceAll(RegExp(r'^[a-z]+_'), '').replaceAll('.mp3', '');
  if (!bare.startsWith('ch')) return false;
  final nums = bare.substring(2).split('_');
  if (nums.length == 1) {
    final n = int.tryParse(nums[0]);
    return n == chapterNumber;
  }
  if (nums.length == 2) {
    final start = int.tryParse(nums[0]);
    final end = int.tryParse(nums[1]);
    if (start == null || end == null) return false;
    return chapterNumber >= start && chapterNumber <= end;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Satcharitra audio — full chapter sets per language
// ---------------------------------------------------------------------------

const List<SatcharitaLanguage> kSatcharitaAudio = [
  SatcharitaLanguage(
    name: 'Marathi',
    displayName: 'मराठी',
    chapters: [
      AudioTrack(title: 'अध्याय १', fileName: 'mr_ch01.mp3'),
      AudioTrack(title: 'अध्याय २', fileName: 'mr_ch02.mp3'),
      AudioTrack(title: 'अध्याय ३', fileName: 'mr_ch03.mp3'),
      AudioTrack(title: 'अध्याय ४', fileName: 'mr_ch04.mp3'),
      AudioTrack(title: 'अध्याय ५', fileName: 'mr_ch05.mp3'),
      AudioTrack(title: 'अध्याय ६', fileName: 'mr_ch06.mp3'),
      AudioTrack(title: 'अध्याय ७', fileName: 'mr_ch07.mp3'),
      AudioTrack(title: 'अध्याय ८', fileName: 'mr_ch08.mp3'),
      AudioTrack(title: 'अध्याय ९', fileName: 'mr_ch09.mp3'),
      AudioTrack(title: 'अध्याय १०', fileName: 'mr_ch10.mp3'),
      AudioTrack(title: 'अध्याय ११', fileName: 'mr_ch11.mp3'),
      AudioTrack(title: 'अध्याय १२', fileName: 'mr_ch12.mp3'),
      AudioTrack(title: 'अध्याय १३', fileName: 'mr_ch13.mp3'),
      AudioTrack(title: 'अध्याय १४', fileName: 'mr_ch14.mp3'),
      AudioTrack(title: 'अध्याय १५', fileName: 'mr_ch15.mp3'),
      AudioTrack(title: 'अध्याय १६', fileName: 'mr_ch16.mp3'),
      AudioTrack(title: 'अध्याय १७', fileName: 'mr_ch17.mp3'),
      AudioTrack(title: 'अध्याय १८', fileName: 'mr_ch18.mp3'),
      AudioTrack(title: 'अध्याय १९', fileName: 'mr_ch19.mp3'),
      AudioTrack(title: 'अध्याय २०', fileName: 'mr_ch20.mp3'),
      AudioTrack(title: 'अध्याय २१', fileName: 'mr_ch21.mp3'),
      AudioTrack(title: 'अध्याय २२', fileName: 'mr_ch22.mp3'),
      AudioTrack(title: 'अध्याय २३', fileName: 'mr_ch23.mp3'),
      AudioTrack(title: 'अध्याय २४', fileName: 'mr_ch24.mp3'),
      AudioTrack(title: 'अध्याय २५', fileName: 'mr_ch25.mp3'),
      AudioTrack(title: 'अध्याय २६', fileName: 'mr_ch26.mp3'),
      AudioTrack(title: 'अध्याय २७', fileName: 'mr_ch27.mp3'),
      AudioTrack(title: 'अध्याय २८', fileName: 'mr_ch28.mp3'),
      AudioTrack(title: 'अध्याय २९', fileName: 'mr_ch29.mp3'),
      AudioTrack(title: 'अध्याय ३०', fileName: 'mr_ch30.mp3'),
      AudioTrack(title: 'अध्याय ३१', fileName: 'mr_ch31.mp3'),
      AudioTrack(title: 'अध्याय ३२', fileName: 'mr_ch32.mp3'),
      AudioTrack(title: 'अध्याय ३३', fileName: 'mr_ch33.mp3'),
      AudioTrack(title: 'अध्याय ३४', fileName: 'mr_ch34.mp3'),
      AudioTrack(title: 'अध्याय ३५', fileName: 'mr_ch35.mp3'),
      AudioTrack(title: 'अध्याय ३६', fileName: 'mr_ch36.mp3'),
      AudioTrack(title: 'अध्याय ३७', fileName: 'mr_ch37.mp3'),
      AudioTrack(title: 'अध्याय ३८', fileName: 'mr_ch38.mp3'),
      AudioTrack(title: 'अध्याय ३९', fileName: 'mr_ch39.mp3'),
      AudioTrack(title: 'अध्याय ४०', fileName: 'mr_ch40.mp3'),
      AudioTrack(title: 'अध्याय ४१', fileName: 'mr_ch41.mp3'),
      AudioTrack(title: 'अध्याय ४२', fileName: 'mr_ch42.mp3'),
      AudioTrack(title: 'अध्याय ४३', fileName: 'mr_ch43.mp3'),
      AudioTrack(title: 'अध्याय ४४', fileName: 'mr_ch44.mp3'),
      AudioTrack(title: 'अध्याय ४५', fileName: 'mr_ch45.mp3'),
      AudioTrack(title: 'अध्याय ४६', fileName: 'mr_ch46.mp3'),
      AudioTrack(title: 'अध्याय ४७', fileName: 'mr_ch47.mp3'),
      AudioTrack(title: 'अध्याय ४८', fileName: 'mr_ch48.mp3'),
      AudioTrack(title: 'अध्याय ४९', fileName: 'mr_ch49.mp3'),
      AudioTrack(title: 'अध्याय ५०', fileName: 'mr_ch50.mp3'),
      AudioTrack(title: 'अध्याय ५१', fileName: 'mr_ch51.mp3'),
      AudioTrack(title: 'अध्याय ५२', fileName: 'mr_ch52.mp3'),
      AudioTrack(title: 'अध्याय ५३', fileName: 'mr_ch53.mp3'),
      AudioTrack(title: 'अध्याय ५४', fileName: 'mr_ch54.mp3'),
    ],
  ),
  SatcharitaLanguage(
    name: 'Marathi-Ovi',
    displayName: 'मराठी (ओवी)',
    chapters: [
      AudioTrack(title: 'अध्याय १', fileName: 'mr_ovi_ch01.mp3'),
      AudioTrack(title: 'अध्याय २', fileName: 'mr_ovi_ch02.mp3'),
      AudioTrack(title: 'अध्याय ३', fileName: 'mr_ovi_ch03.mp3'),
      AudioTrack(title: 'अध्याय ४', fileName: 'mr_ovi_ch04.mp3'),
      AudioTrack(title: 'अध्याय ५', fileName: 'mr_ovi_ch05.mp3'),
      AudioTrack(title: 'अध्याय ६', fileName: 'mr_ovi_ch06.mp3'),
      AudioTrack(title: 'अध्याय ७', fileName: 'mr_ovi_ch07.mp3'),
      AudioTrack(title: 'अध्याय ८', fileName: 'mr_ovi_ch08.mp3'),
      AudioTrack(title: 'अध्याय ९', fileName: 'mr_ovi_ch09.mp3'),
      AudioTrack(title: 'अध्याय १०', fileName: 'mr_ovi_ch10.mp3'),
      AudioTrack(title: 'अध्याय ११', fileName: 'mr_ovi_ch11.mp3'),
      AudioTrack(title: 'अध्याय १२', fileName: 'mr_ovi_ch12.mp3'),
      AudioTrack(title: 'अध्याय १३', fileName: 'mr_ovi_ch13.mp3'),
      AudioTrack(title: 'अध्याय १४', fileName: 'mr_ovi_ch14.mp3'),
      AudioTrack(title: 'अध्याय १५', fileName: 'mr_ovi_ch15.mp3'),
      AudioTrack(title: 'अध्याय १६', fileName: 'mr_ovi_ch16.mp3'),
      AudioTrack(title: 'अध्याय १७', fileName: 'mr_ovi_ch17.mp3'),
      AudioTrack(title: 'अध्याय १८', fileName: 'mr_ovi_ch18.mp3'),
      AudioTrack(title: 'अध्याय १९', fileName: 'mr_ovi_ch19.mp3'),
      AudioTrack(title: 'अध्याय २०', fileName: 'mr_ovi_ch20.mp3'),
      AudioTrack(title: 'अध्याय २१', fileName: 'mr_ovi_ch21.mp3'),
      AudioTrack(title: 'अध्याय २२', fileName: 'mr_ovi_ch22.mp3'),
      AudioTrack(title: 'अध्याय २३', fileName: 'mr_ovi_ch23.mp3'),
      AudioTrack(title: 'अध्याय २४', fileName: 'mr_ovi_ch24.mp3'),
      AudioTrack(title: 'अध्याय २५', fileName: 'mr_ovi_ch25.mp3'),
      AudioTrack(title: 'अध्याय २६', fileName: 'mr_ovi_ch26.mp3'),
      AudioTrack(title: 'अध्याय २७', fileName: 'mr_ovi_ch27.mp3'),
      AudioTrack(title: 'अध्याय २८', fileName: 'mr_ovi_ch28.mp3'),
      AudioTrack(title: 'अध्याय २९', fileName: 'mr_ovi_ch29.mp3'),
      AudioTrack(title: 'अध्याय ३०', fileName: 'mr_ovi_ch30.mp3'),
      AudioTrack(title: 'अध्याय ३१', fileName: 'mr_ovi_ch31.mp3'),
      AudioTrack(title: 'अध्याय ३२', fileName: 'mr_ovi_ch32.mp3'),
      AudioTrack(title: 'अध्याय ३३', fileName: 'mr_ovi_ch33.mp3'),
      AudioTrack(title: 'अध्याय ३४', fileName: 'mr_ovi_ch34.mp3'),
      AudioTrack(title: 'अध्याय ३५', fileName: 'mr_ovi_ch35.mp3'),
      AudioTrack(title: 'अध्याय ३६', fileName: 'mr_ovi_ch36.mp3'),
      AudioTrack(title: 'अध्याय ३७', fileName: 'mr_ovi_ch37.mp3'),
      AudioTrack(title: 'अध्याय ३८', fileName: 'mr_ovi_ch38.mp3'),
      AudioTrack(title: 'अध्याय ३९', fileName: 'mr_ovi_ch39.mp3'),
      AudioTrack(title: 'अध्याय ४०', fileName: 'mr_ovi_ch40.mp3'),
      AudioTrack(title: 'अध्याय ४१', fileName: 'mr_ovi_ch41.mp3'),
      AudioTrack(title: 'अध्याय ४२', fileName: 'mr_ovi_ch42.mp3'),
      AudioTrack(title: 'अध्याय ४३', fileName: 'mr_ovi_ch43.mp3'),
      AudioTrack(title: 'अध्याय ४४', fileName: 'mr_ovi_ch44.mp3'),
      AudioTrack(title: 'अध्याय ४५', fileName: 'mr_ovi_ch45.mp3'),
      AudioTrack(title: 'अध्याय ४६', fileName: 'mr_ovi_ch46.mp3'),
      AudioTrack(title: 'अध्याय ४७', fileName: 'mr_ovi_ch47.mp3'),
      AudioTrack(title: 'अध्याय ४८', fileName: 'mr_ovi_ch48.mp3'),
      AudioTrack(title: 'अध्याय ४९', fileName: 'mr_ovi_ch49.mp3'),
      AudioTrack(title: 'अध्याय ५०', fileName: 'mr_ovi_ch50.mp3'),
      AudioTrack(title: 'अध्याय ५१', fileName: 'mr_ovi_ch51.mp3'),
      AudioTrack(title: 'अध्याय ५२', fileName: 'mr_ovi_ch52.mp3'),
      AudioTrack(title: 'अध्याय ५३', fileName: 'mr_ovi_ch53.mp3'),
    ],
  ),
  SatcharitaLanguage(
    name: 'Hindi',
    displayName: 'हिंदी',
    chapters: [
      AudioTrack(title: 'अध्याय १', fileName: 'hi_ch01.mp3'),
      AudioTrack(title: 'अध्याय २', fileName: 'hi_ch02.mp3'),
      AudioTrack(title: 'अध्याय ३', fileName: 'hi_ch03.mp3'),
      AudioTrack(title: 'अध्याय ४', fileName: 'hi_ch04.mp3'),
      AudioTrack(title: 'अध्याय ५', fileName: 'hi_ch05.mp3'),
      AudioTrack(title: 'अध्याय ६', fileName: 'hi_ch06.mp3'),
      AudioTrack(title: 'अध्याय ७', fileName: 'hi_ch07.mp3'),
      AudioTrack(title: 'अध्याय ८', fileName: 'hi_ch08.mp3'),
      AudioTrack(title: 'अध्याय ९', fileName: 'hi_ch09.mp3'),
      AudioTrack(title: 'अध्याय १०', fileName: 'hi_ch10.mp3'),
      AudioTrack(title: 'अध्याय ११', fileName: 'hi_ch11.mp3'),
      AudioTrack(title: 'अध्याय १२', fileName: 'hi_ch12.mp3'),
      AudioTrack(title: 'अध्याय १३', fileName: 'hi_ch13.mp3'),
      AudioTrack(title: 'अध्याय १४', fileName: 'hi_ch14.mp3'),
      AudioTrack(title: 'अध्याय १५', fileName: 'hi_ch15.mp3'),
      AudioTrack(title: 'अध्याय १६–१७', fileName: 'hi_ch16_17.mp3'),
      AudioTrack(title: 'अध्याय १८–१९', fileName: 'hi_ch18_19.mp3'),
      AudioTrack(title: 'अध्याय २०', fileName: 'hi_ch20.mp3'),
      AudioTrack(title: 'अध्याय २१', fileName: 'hi_ch21.mp3'),
      AudioTrack(title: 'अध्याय २२', fileName: 'hi_ch22.mp3'),
      AudioTrack(title: 'अध्याय २३', fileName: 'hi_ch23.mp3'),
      AudioTrack(title: 'अध्याय २४', fileName: 'hi_ch24.mp3'),
      AudioTrack(title: 'अध्याय २५', fileName: 'hi_ch25.mp3'),
      AudioTrack(title: 'अध्याय २६', fileName: 'hi_ch26.mp3'),
      AudioTrack(title: 'अध्याय २७', fileName: 'hi_ch27.mp3'),
      AudioTrack(title: 'अध्याय २८', fileName: 'hi_ch28.mp3'),
      AudioTrack(title: 'अध्याय २९', fileName: 'hi_ch29.mp3'),
      AudioTrack(title: 'अध्याय ३०', fileName: 'hi_ch30.mp3'),
      AudioTrack(title: 'अध्याय ३१', fileName: 'hi_ch31.mp3'),
      AudioTrack(title: 'अध्याय ३२', fileName: 'hi_ch32.mp3'),
      AudioTrack(title: 'अध्याय ३३', fileName: 'hi_ch33.mp3'),
      AudioTrack(title: 'अध्याय ३४', fileName: 'hi_ch34.mp3'),
      AudioTrack(title: 'अध्याय ३५', fileName: 'hi_ch35.mp3'),
      AudioTrack(title: 'अध्याय ३६', fileName: 'hi_ch36.mp3'),
      AudioTrack(title: 'अध्याय ३७', fileName: 'hi_ch37.mp3'),
      AudioTrack(title: 'अध्याय ३८', fileName: 'hi_ch38.mp3'),
      AudioTrack(title: 'अध्याय ३९', fileName: 'hi_ch39.mp3'),
      AudioTrack(title: 'अध्याय ४०', fileName: 'hi_ch40.mp3'),
      AudioTrack(title: 'अध्याय ४१', fileName: 'hi_ch41.mp3'),
      AudioTrack(title: 'अध्याय ४२', fileName: 'hi_ch42.mp3'),
      AudioTrack(title: 'अध्याय ४३–४४', fileName: 'hi_ch43_44.mp3'),
      AudioTrack(title: 'अध्याय ४५', fileName: 'hi_ch45.mp3'),
      AudioTrack(title: 'अध्याय ४६', fileName: 'hi_ch46.mp3'),
      AudioTrack(title: 'अध्याय ४७', fileName: 'hi_ch47.mp3'),
      AudioTrack(title: 'अध्याय ४८', fileName: 'hi_ch48.mp3'),
      AudioTrack(title: 'अध्याय ४९', fileName: 'hi_ch49.mp3'),
      AudioTrack(title: 'अध्याय ५०', fileName: 'hi_ch50.mp3'),
      AudioTrack(title: 'अध्याय ५१', fileName: 'hi_ch51.mp3'),
      AudioTrack(title: 'साईवचन', fileName: 'hi_saivachan.mp3'),
    ],
  ),
  SatcharitaLanguage(
    name: 'Telugu',
    displayName: 'తెలుగు',
    chapters: [
      AudioTrack(title: 'ఉపోద్ఘాతం', fileName: 'te_upodghatam.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧', fileName: 'te_ch01.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨', fileName: 'te_ch02.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩', fileName: 'te_ch03.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪', fileName: 'te_ch04.mp3'),
      AudioTrack(title: 'అధ్యాయం ౫', fileName: 'te_ch05.mp3'),
      AudioTrack(title: 'అధ్యాయం ౬', fileName: 'te_ch06.mp3'),
      AudioTrack(title: 'అధ్యాయం ౭', fileName: 'te_ch07.mp3'),
      AudioTrack(title: 'అధ్యాయం ౮', fileName: 'te_ch08.mp3'),
      AudioTrack(title: 'అధ్యాయం ౯', fileName: 'te_ch09.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౦', fileName: 'te_ch10.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౧', fileName: 'te_ch11.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౨', fileName: 'te_ch12.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౩', fileName: 'te_ch13.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౪', fileName: 'te_ch14.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౫', fileName: 'te_ch15.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౬–౧౭', fileName: 'te_ch16_17.mp3'),
      AudioTrack(title: 'అధ్యాయం ౧౮–౧౯', fileName: 'te_ch18_19.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౦', fileName: 'te_ch20.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౧', fileName: 'te_ch21.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౨', fileName: 'te_ch22.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౩', fileName: 'te_ch23.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౪', fileName: 'te_ch24.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౫', fileName: 'te_ch25.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౬', fileName: 'te_ch26.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౭', fileName: 'te_ch27.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౮', fileName: 'te_ch28.mp3'),
      AudioTrack(title: 'అధ్యాయం ౨౯', fileName: 'te_ch29.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౦', fileName: 'te_ch30.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౧', fileName: 'te_ch31.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౨', fileName: 'te_ch32.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౩', fileName: 'te_ch33.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౪', fileName: 'te_ch34.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౫', fileName: 'te_ch35.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౬', fileName: 'te_ch36.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౭', fileName: 'te_ch37.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౮', fileName: 'te_ch38.mp3'),
      AudioTrack(title: 'అధ్యాయం ౩౯', fileName: 'te_ch39.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౦', fileName: 'te_ch40.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౧', fileName: 'te_ch41.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౨', fileName: 'te_ch42.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౩–౪౪', fileName: 'te_ch43_44.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౫', fileName: 'te_ch45.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౬', fileName: 'te_ch46.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౭', fileName: 'te_ch47.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౮', fileName: 'te_ch48.mp3'),
      AudioTrack(title: 'అధ్యాయం ౪౯', fileName: 'te_ch49.mp3'),
      AudioTrack(title: 'అధ్యాయం ౫౦', fileName: 'te_ch50.mp3'),
      AudioTrack(title: 'అధ్యాయం ౫౧', fileName: 'te_ch51.mp3'),
    ],
  ),
  SatcharitaLanguage(
    name: 'Tamil',
    displayName: 'தமிழ்',
    chapters: [
      AudioTrack(title: 'அத்தியாயம் ௧', fileName: 'ta_ch01.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨', fileName: 'ta_ch02.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩', fileName: 'ta_ch03.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪', fileName: 'ta_ch04.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௫', fileName: 'ta_ch05.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௬', fileName: 'ta_ch06.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௭', fileName: 'ta_ch07.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௮', fileName: 'ta_ch08.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௯', fileName: 'ta_ch09.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௦', fileName: 'ta_ch10.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௧', fileName: 'ta_ch11.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௨', fileName: 'ta_ch12.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௩', fileName: 'ta_ch13.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௪', fileName: 'ta_ch14.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௫', fileName: 'ta_ch15.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௬–௧௭', fileName: 'ta_ch16_17.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௧௮–௧௯', fileName: 'ta_ch18_19.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௦', fileName: 'ta_ch20.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௧', fileName: 'ta_ch21.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௨', fileName: 'ta_ch22.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௩', fileName: 'ta_ch23.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௪', fileName: 'ta_ch24.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௫', fileName: 'ta_ch25.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௬', fileName: 'ta_ch26.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௭', fileName: 'ta_ch27.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௮', fileName: 'ta_ch28.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௨௯', fileName: 'ta_ch29.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௦', fileName: 'ta_ch30.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௧', fileName: 'ta_ch31.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௨', fileName: 'ta_ch32.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௩', fileName: 'ta_ch33.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௪', fileName: 'ta_ch34.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௫', fileName: 'ta_ch35.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௬', fileName: 'ta_ch36.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௭', fileName: 'ta_ch37.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௮', fileName: 'ta_ch38.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௩௯', fileName: 'ta_ch39.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௦', fileName: 'ta_ch40.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௧', fileName: 'ta_ch41.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௨', fileName: 'ta_ch42.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௩–௪௪', fileName: 'ta_ch43_44.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௫', fileName: 'ta_ch45.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௬', fileName: 'ta_ch46.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௭', fileName: 'ta_ch47.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௮', fileName: 'ta_ch48.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௪௯', fileName: 'ta_ch49.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௫௦', fileName: 'ta_ch50.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௫௧', fileName: 'ta_ch51.mp3'),
      AudioTrack(title: 'அத்தியாயம் ௫௨', fileName: 'ta_ch52.mp3'),
    ],
  ),
];

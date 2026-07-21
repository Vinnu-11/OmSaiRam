// Om Sai Ram
// Baba's teachings and quotes from Sai Satcharita.

class SaiQuote {
  final String text;
  final String source;
  const SaiQuote(this.text, this.source);
}

const List<SaiQuote> kSaiQuotes = [
  SaiQuote(
    'Why are you afraid? I am always with you. Wherever you are, I am there.',
    'Sai Satcharita, Ch. 4',
  ),
  SaiQuote(
    'Look at Me and I shall look at you.',
    'Sai Satcharita, Ch. 2',
  ),
  SaiQuote(
    'Give food to the hungry, water to the thirsty, and clothes to the naked. God will be pleased.',
    'Sai Satcharita, Ch. 19',
  ),
  SaiQuote(
    'Trust in Me and your prayer shall be answered.',
    'Sai Satcharita, Ch. 3',
  ),
  SaiQuote(
    'I never forsake My devotees. I always think of those who remember Me with love.',
    'Sai Satcharita, Ch. 7',
  ),
  SaiQuote(
    'Stay near Me. The one who comes to Me for shelter, I take care of.',
    'Sai Satcharita, Ch. 9',
  ),
  SaiQuote(
    'Do not be afraid. My eye is ever on those who love Me.',
    'Sai Satcharita, Ch. 14',
  ),
  SaiQuote(
    'If you make Me your sole refuge, I shall certainly save you.',
    'Sai Satcharita, Ch. 3',
  ),
  SaiQuote(
    'Before you begin any work, think of Me; the work shall be accomplished without hindrance.',
    'Sai Satcharita, Ch. 1',
  ),
  SaiQuote(
    'Have patience, it will be well with you in the end.',
    'Sai Satcharita, Ch. 17',
  ),
  SaiQuote(
    'God is not so distant. He dwells in your own heart.',
    'Sai Satcharita, Ch. 27',
  ),
  SaiQuote(
    'Surrender to Me wholeheartedly and I will take up all your responsibilities.',
    'Sai Satcharita, Ch. 32',
  ),
  SaiQuote(
    'My treasure is open to all. No one need be anxious. Dig deep and you shall find.',
    'Sai Satcharita, Ch. 20',
  ),
  SaiQuote(
    'Bear all and do nothing. Hear all and say nothing. Give all and take nothing.',
    'Sai Satcharita, Ch. 17',
  ),
  SaiQuote(
    'Whatever you do, wherever you are, always know that I am watching.',
    'Sai Satcharita, Ch. 12',
  ),
  SaiQuote(
    'Shraddha and Saburi — faith and patience — are the two keys to liberation.',
    'Sai Satcharita, Ch. 2',
  ),
  SaiQuote(
    'Do not be greedy. Be contented with what God has given you.',
    'Sai Satcharita, Ch. 19',
  ),
  SaiQuote(
    'I am the wind, I am the sky, I am the fire. I am omnipresent.',
    'Sai Satcharita, Ch. 5',
  ),
  SaiQuote(
    'He who loves Me and remembers Me constantly, I am ever with him.',
    'Sai Satcharita, Ch. 33',
  ),
  SaiQuote(
    'Seek Me with a pure heart and you shall surely find Me.',
    'Sai Satcharita, Ch. 8',
  ),
  SaiQuote(
    'Do not fight with anyone. Do not be angry with anyone. Live in peace.',
    'Sai Satcharita, Ch. 16',
  ),
  SaiQuote(
    'If anyone is in distress and comes to Me, I shall help. This is My promise.',
    'Sai Satcharita, Ch. 31',
  ),
  SaiQuote(
    'I am always present with you. Remove the veil of ignorance and you will see Me.',
    'Sai Satcharita, Ch. 44',
  ),
  SaiQuote(
    'The one who thinks of Me, him I think of. He who seeks refuge in Me is always safe.',
    'Sai Satcharita, Ch. 36',
  ),
  SaiQuote(
    'My grace flows to those who call on Me sincerely, day or night.',
    'Sai Satcharita, Ch. 41',
  ),
  SaiQuote(
    'God has no love for the one who says, "Give, give." He loves those who give freely.',
    'Sai Satcharita, Ch. 19',
  ),
  SaiQuote(
    'Do not be under the delusion that I am only here in Shirdi. I am everywhere.',
    'Sai Satcharita, Ch. 4',
  ),
  SaiQuote(
    'Let go of ego and I shall guide every step of your path.',
    'Sai Satcharita, Ch. 21',
  ),
  SaiQuote(
    'My devotees are never without protection. I am the guardian of all who take My name.',
    'Sai Satcharita, Ch. 39',
  ),
  SaiQuote(
    'Wealth that is hoarded brings no happiness. Share it and it multiplies in your heart.',
    'Sai Satcharita, Ch. 25',
  ),
];

/// Returns the quote for today — changes once per calendar day.
SaiQuote get todaysSaiQuote {
  final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
  return kSaiQuotes[dayOfYear % kSaiQuotes.length];
}

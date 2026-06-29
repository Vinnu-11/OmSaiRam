// Om Sai Ram
// Application-wide string constants.

/// Centralized string constants for the app.
/// Keeps UI text in one place for easy localization later.
class AppStrings {
  AppStrings._();

  // App
  static const String appName = 'Om Sai Ram';
  static const String appTagline = 'Group readings of the Sai Satcharita';

  // Auth
  static const String login = 'Login';
  static const String signup = 'Sign Up';
  static const String email = 'Email';
  static const String password = 'Password';
  static const String confirmPassword = 'Confirm Password';
  static const String fullName = 'Full Name';
  static const String forgotPassword = 'Forgot Password?';
  static const String orContinueWith = 'Or continue with';
  static const String signInWithGoogle = 'Continue with Google';
  static const String signInWithApple = 'Continue with Apple';
  static const String dontHaveAccount = "Don't have an account? ";
  static const String alreadyHaveAccount = 'Already have an account? ';
  static const String resetPassword = 'Reset Password';

  // Navigation
  static const String home = 'Home';
  static const String groups = 'Groups';
  static const String reader = 'Reader';
  static const String profile = 'Profile';

  // Groups
  static const String createGroup = 'Create Group';
  static const String joinGroup = 'Join Group';
  static const String groupName = 'Group Name';
  static const String groupDescription = 'Description (optional)';
  static const String inviteCode = 'Invite Code';
  static const String members = 'Members';
  static const String assignments = 'Assignments';
  static const String chapterWise = 'Chapter-wise';
  static const String weeklySaptah = 'Weekly Saptah';

  // Reader
  static const String chapters = 'Chapters';
  static const String chapter = 'Chapter';
  static const String saiSatcharita = 'Shri Sai Satcharita';

  // Progress
  static const String notStarted = 'Not Started';
  static const String inProgress = 'In Progress';
  static const String completed = 'Completed';
  static const String markAsRead = 'Mark as Read';

  // FAQ
  static const String faq = 'FAQ';
  static const String frequentlyAskedQuestions = 'Frequently Asked Questions';

  // Profile
  static const String editProfile = 'Edit Profile';
  static const String settings = 'Settings';
  static const String language = 'Language';
  static const String notifications = 'Notifications';
  static const String logout = 'Logout';
  static const String about = 'About';

  // Errors
  static const String emailRequired = 'Email is required';
  static const String invalidEmail = 'Please enter a valid email';
  static const String passwordRequired = 'Password is required';
  static const String passwordTooShort = 'Password must be at least 8 characters';
  static const String passwordsDoNotMatch = 'Passwords do not match';
  static const String nameRequired = 'Name is required';
  static const String somethingWentWrong = 'Something went wrong. Please try again.';
}

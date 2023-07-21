#!perl
use 5.020;
use Win32::OLE;

my $sapi = Win32::OLE->CreateObject('SAPI.SpVoice');
$sapi->Speak('<LANG LANGID="9">Do you remember? when we used to sit</LANG>');
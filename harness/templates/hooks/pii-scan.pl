#!/usr/bin/env perl
# Quét PII trong $ENV{PII_TEXT}. In "kind: <masked>" mỗi dòng, không in value đầy đủ.
# Arg1 (tuỳ chọn): file allowlist — mỗi dòng 1 chuỗi được bỏ qua.
# ponytail: regex heuristic VN (SĐT, CCCD, email, số nhà + đường/ngõ, toạ độ VN);
#   không bắt tên người / địa chỉ viết tự do — cần NER nếu muốn phủ hết.
use strict; use warnings; use utf8;
binmode STDOUT, ':utf8';

my $text = $ENV{PII_TEXT} // '';
utf8::decode($text);

my $allow = $ARGV[0] // '';
if ($allow && open my $fh, '<:utf8', $allow) {
  while (my $l = <$fh>) { chomp $l; next if $l =~ /^\s*(#|$)/; $text =~ s/\Q$l\E//g; }
}

my $mask = sub { my $s = shift; length($s) <= 6 ? '***' : substr($s,0,3).'***'.substr($s,-2) };
my %seen;
my @rules = (
  [phone => qr/(?<![\d.])(?:\+?84|0)[ .-]?[35789]\d(?:[ .-]?\d){7}(?![\d.])/],
  [cccd  => qr/(?<![\d.])0\d{11}(?![\d.])/],
  [email => qr/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/],
  [address => qr/(?<!\w)\d+[A-Za-z]?(?:\/\d+)*\s+(?:đường|phố|ngõ|ngách|hẻm|kiệt|duong|pho)\s+\w/i],
  [address => qr/(?<!\w)(?:ngõ|ngách|hẻm|kiệt)\s+\d+/i],
  [gps => qr/(?<![\d.])(?:[89]|1\d|2[0-3])\.\d{4,}\s*,\s*1(?:0[2-9]|10)\.\d{4,}/],
);
my $email_ok = qr/\@(?:anthropic\.com|users\.noreply\.github\.com)$|\@(?:[\w-]+\.)*(?:example\.\w+|test|local|invalid)$|^(?:no-?reply|git)\@/i;

for my $r (@rules) {
  my ($kind, $re) = @$r;
  while ($text =~ /($re)/g) {
    my $v = $1;
    next if $kind eq 'email' && $v =~ $email_ok;
    print "$kind: ", $mask->($v), "\n" unless $seen{"$kind$v"}++;
  }
}

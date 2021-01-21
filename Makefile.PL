use inc::Module::Install;

RTx     'RT-Extension-NotifySMS';
license 'gplv2';
repository 'https://github.com/bestpractical/rt-extension-NotifySMS';

requires_rt '4.4.0';
rt_too_new '5.1.0';

sign;
WriteAll;

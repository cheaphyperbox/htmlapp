"""Check the packaged archives, not just pre-package build products."""
import plistlib, subprocess, tempfile, zipfile, pathlib, sys
for archive in sys.argv[1:]:
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            z.extractall(tmp)
        app=pathlib.Path(tmp)/'Payload/HTMLApp.app'
        for bundle,expected in [(app,'com.mekabrine.htmlapp'),(app/'PlugIns/HTMLAppWidgets.appex','com.mekabrine.htmlapp.widgets')]:
            info=plistlib.loads((bundle/'Info.plist').read_bytes())
            assert info['CFBundleIdentifier']==expected
            assert float(info['MinimumOSVersion'])<=16.0
            assert set(info['UIDeviceFamily'])=={1,2}
            binary=bundle/info['CFBundleExecutable']
            assert binary.is_file()
            if bundle.suffix=='.appex': assert info['NSExtension']['NSExtensionPointIdentifier']=='com.apple.widgetkit-extension'
            if 'TrollStore' in archive:
                ent=plistlib.loads(subprocess.check_output(['ldid','-e',str(binary)]))
                assert ent['com.apple.security.application-groups']==['group.com.mekabrine.htmlapp']
                print(archive,bundle.name,'embedded App Group verified')
            else:
                ent=plistlib.loads((bundle/'WidgetSigningRequirements.plist').read_bytes())
                assert ent['com.apple.security.application-groups']==['group.com.mekabrine.htmlapp']
                print(archive,bundle.name,'unsigned signing metadata verified; profile authorization NOT verified')

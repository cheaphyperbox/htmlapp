"""macOS: validate the exported Feather-signed IPA without printing profile secrets."""
import pathlib, plistlib, subprocess, sys, tempfile, zipfile, datetime
with tempfile.TemporaryDirectory() as directory:
    with zipfile.ZipFile(sys.argv[1]) as z: z.extractall(directory)
    app=next((pathlib.Path(directory)/'Payload').glob('*.app'))
    extension=app/'PlugIns/HTMLAppWidgets.appex'
    group='group.com.mekabrine.htmlapp'
    teams = set()
    for bundle in [app,extension]:
        assert bundle.is_dir(), 'Widget extension missing'
        subprocess.run(['codesign','--verify','--strict',str(bundle)],check=True,capture_output=True)
        raw=subprocess.run(['codesign','-d','--entitlements',':-',str(bundle)],check=True,capture_output=True).stdout
        ent=plistlib.loads(raw)
        raw=subprocess.run(['security','cms','-D','-i',str(bundle/'embedded.mobileprovision')],check=True,capture_output=True).stdout
        decoded=plistlib.loads(raw)
        assert decoded['ExpirationDate'] > datetime.datetime.utcnow(), 'Provisioning profile expired'
        profile=decoded['Entitlements']
        assert group in ent.get('com.apple.security.application-groups',[]), 'Signed group missing'
        assert group in profile.get('com.apple.security.application-groups',[]), 'Profile does not authorize group'
        assert ent.get('application-identifier')==profile.get('application-identifier'), 'App identifier mismatch'
        assert ent.get('com.apple.developer.team-identifier')==profile.get('com.apple.developer.team-identifier'), 'Team mismatch'
        teams.add(ent.get('com.apple.developer.team-identifier'))
        print(bundle.name+': signature verified; App Group, team, and app identifier match profile')
    assert len(teams)==1 and None not in teams, "App and extension must use the same team"

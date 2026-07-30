'use strict';

const assert = require('assert');
const Profile = require('../launcher/web/modules/workbench-profile.js');

const valid = Profile.validProfiles;

valid.forEach(profile => assert.strictEqual(Profile.requireProfile(profile), profile));
assert(Object.isFrozen(valid));
['', null, undefined, 'transfer', 'not-real'].forEach(profile => {
    assert.throws(() => Profile.requireProfile(profile), TypeError);
});

const root = {
    value:'catalog-decision',
    setAttribute(name, value) {
        assert.strictEqual(name, 'data-profile');
        this.value = value;
    }
};
const shell = {_root:root, _profile:root.value, _destroyed:false, _destroying:false};
assert.throws(() => Profile.setProfile.call(shell, 'not-real'), TypeError);
assert.strictEqual(root.value, 'catalog-decision');
assert.strictEqual(shell._profile, 'catalog-decision');
assert.strictEqual(Profile.setProfile.call(shell, 'transfer-pair'), true);
assert.strictEqual(root.value, 'transfer-pair');
assert.strictEqual(shell._profile, 'transfer-pair');
shell._destroyed = true;
assert.strictEqual(Profile.setProfile.call(shell, 'character-build'), false);
assert.strictEqual(root.value, 'transfer-pair');

process.stdout.write('workbench profile tests passed: closed enum + atomic projection\n');

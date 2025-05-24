'use strict';

var re = require('data-uri-regex');

module.exports = function (data) {
	return (data && re().test(data)) === true;
};

'use strict';

module.exports = function () {
	// data-uri scheme
	// data:[<media type>][;charset=<character set>][;base64],<data>
	return new RegExp(/^(data:)([\w\/\+]+);(charset=[\w-]+|base64).*,(.*)/gi);
};

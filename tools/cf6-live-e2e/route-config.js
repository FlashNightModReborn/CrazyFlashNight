'use strict';
const ROUTES=Object.freeze({
    historical:Object.freeze({id:'historical',playTarget:'cf6-sting',slot:'cf7_agent_cf6_sting_20261021',
        chapterPath:'data/stages/books/cf6-sting.runtime.json',level:60,experience:157526193,enhancement:11}),
    type61:Object.freeze({id:'type61',playTarget:'cf6-sting.type61',slot:'cf7_agent_cf6_type61_20261026',
        chapterPath:'data/stages/books/cf6-type61.runtime.json',level:35,experience:17372868,enhancement:1})
});
function resolveRoute(id='historical') {
    if(typeof id!=='string'||!Object.prototype.hasOwnProperty.call(ROUTES,id))throw Error('unsupported CF6 route');
    return ROUTES[id];
}
module.exports={resolveRoute,ROUTES};

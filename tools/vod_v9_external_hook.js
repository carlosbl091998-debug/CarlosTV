'use strict';
let installed = false;
function tryInstall() {
  if (installed || !Java.available) return;
  Java.perform(function () {
    try {
      const Z = Java.use('cb.z1');
      const g = Z.g.overload('java.lang.Object','java.lang.String','boolean','java.lang.Class','java.lang.String','java.util.HashMap','java.lang.String','boolean');
      g.implementation = function (body, uri, secure, responseClass, method, headers, serviceName, flag) {
        const u = uri ? uri.toString() : '';
        if (u.indexOf('api/portalCore/v10/startPlayVOD') !== -1) {
          const patched = u.replace('api/portalCore/v10/startPlayVOD', 'api/portalCore/v9/startPlayVOD');
          console.log('[XUPER_VOD_FIX] route ' + u + ' -> ' + patched);
          return g.call(this, body, patched, secure, responseClass, method, headers, serviceName, flag);
        }
        return g.call(this, body, uri, secure, responseClass, method, headers, serviceName, flag);
      };
      installed = true;
      console.log('[XUPER_VOD_FIX] hook installed');
    } catch (e) {
      console.log('[XUPER_VOD_FIX] waiting: ' + e);
    }
  });
}
setInterval(tryInstall, 500);
tryInstall();

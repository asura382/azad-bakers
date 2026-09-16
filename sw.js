const CACHE="azad-bakers-shell-v3";

self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));

self.addEventListener("fetch",e=>{
  if(e.request.method!=="GET")return;
  e.respondWith(
    fetch(e.request).catch(()=>
      caches.match(e.request).then(r=>r||Response.error())
    )
  );
});

self.addEventListener("push",event=>{
  let data={};
  try{data=event.data?event.data.json():{}}
  catch{data={body:event.data?event.data.text():"A new Azad Bakers order has been placed."}}

  event.waitUntil(
    self.registration.showNotification(data.title||"New Azad Bakers order",{
      body:data.body||"A new customer order has been placed.",
      icon:data.icon||"/icons/icon-192.png",
      badge:data.badge||"/icons/icon-192.png",
      tag:data.tag||`azad-order-${Date.now()}`,
      renotify:true,
      requireInteraction:true,
      vibrate:[250,120,250,120,400],
      data:{url:data.url||"/admin/"}
    })
  );
});

self.addEventListener("notificationclick",event=>{
  event.notification.close();
  const target=event.notification.data?.url||"/admin/";
  event.waitUntil(
    clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{
      for(const client of list){
        if("focus" in client){
          if("navigate" in client)client.navigate(new URL(target,self.location.origin).href);
          return client.focus();
        }
      }
      return clients.openWindow(target);
    })
  );
});

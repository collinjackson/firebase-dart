// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "firebase_impl.h"

#import <Firebase.h>

namespace firebase {

::firebase::DataSnapshotPtr toMojoSnapshot(FDataSnapshot* snapshot) {
  ::firebase::DataSnapshotPtr mojoSnapshot(::firebase::DataSnapshot::New());
  mojoSnapshot->key = snapshot.key.UTF8String;
  NSDictionary *valueDictionary = @{@"value": snapshot.value};
  NSData *data = [NSJSONSerialization dataWithJSONObject:valueDictionary
                                                 options:0
                                                   error:nil];
  if (data != nil) {
    NSString *jsonValue = [[NSString alloc] initWithData:data
                                                encoding:NSUTF8StringEncoding];
    mojoSnapshot->jsonValue = jsonValue.UTF8String;
  }
  return mojoSnapshot.Pass();
}

::firebase::ErrorPtr toMojoError(NSError* error) {
  ::firebase::ErrorPtr mojoError(::firebase::Error::New());
  mojoError->code = error.code;
  mojoError->message = error.description.UTF8String;
  return mojoError.Pass();
}

::firebase::AuthDataPtr toMojoAuthData(FAuthData* authData) {
  ::firebase::AuthDataPtr mojoAuthData(::firebase::AuthData::New());
  mojoAuthData->uid = authData.uid.UTF8String;
  mojoAuthData->provider = authData.provider.UTF8String;
  mojoAuthData->token = authData.token.UTF8String;
  return mojoAuthData.Pass();
}

FirebaseImpl::FirebaseImpl(mojo::InterfaceRequest<::firebase::Firebase> request)
    : binding_(this, request.Pass()) {}

FirebaseImpl::~FirebaseImpl() {
  [client_ release];
}

void FirebaseImpl::InitWithUrl(const mojo::String& url) {
  client_ = [[[::Firebase alloc] initWithUrl:@(url.data())] retain];
}

void FirebaseImpl::AddValueEventListener(
    mojo::InterfaceHandle<::firebase::ValueEventListener> interfaceHandle) {
  mojo::InterfacePtr<::firebase::ValueEventListener> ptr =
    mojo::InterfacePtr<::firebase::ValueEventListener>::Create(interfaceHandle.Pass());
  ::firebase::ValueEventListener *listener = ptr.get();
  FirebaseHandle handle = [client_ observeEventType:FEventTypeValue
                                          withBlock:^(FDataSnapshot *snapshot) {
    listener->OnDataChange(toMojoSnapshot(snapshot));
  } withCancelBlock:^(NSError *error) {
    listener->OnCancelled(toMojoError(error));
  }];
  ptr.set_connection_error_handler([this, handle, listener]() {
    [client_ removeObserverWithHandle:handle];
    auto it = std::find_if(value_event_listeners_.begin(),
                           value_event_listeners_.end(),
                           [listener](const ::firebase::ValueEventListenerPtr& p) {
                             return (p.get() == listener);
                           });
    value_event_listeners_.erase(it);
  });
  value_event_listeners_.emplace_back(ptr.Pass());
}

void FirebaseImpl::AddChildEventListener(
    mojo::InterfaceHandle<::firebase::ChildEventListener> interfaceHandle) {
  mojo::InterfacePtr<::firebase::ChildEventListener> ptr =
    mojo::InterfacePtr<::firebase::ChildEventListener>::Create(interfaceHandle.Pass());
  ::firebase::ChildEventListener *listener = ptr.get();
  void (^cancelBlock)(NSError *) = ^(NSError *error) {
    listener->OnCancelled(toMojoError(error));
  };

  void (^addedBlock)(FDataSnapshot *, NSString *) = ^(FDataSnapshot *snapshot, NSString *prevKey) {
    listener->OnChildAdded(toMojoSnapshot(snapshot), prevKey.UTF8String);
  };
  FirebaseHandle addedHandle = [client_ observeEventType:FEventTypeChildAdded
                          andPreviousSiblingKeyWithBlock:addedBlock
                                         withCancelBlock:cancelBlock];

  void (^changedBlock)(FDataSnapshot *, NSString *) = ^(FDataSnapshot *snapshot, NSString *prevKey) {
    listener->OnChildChanged(toMojoSnapshot(snapshot), prevKey.UTF8String);
  };
  FirebaseHandle changedHandle = [client_ observeEventType:FEventTypeChildChanged
                            andPreviousSiblingKeyWithBlock:changedBlock
                                           withCancelBlock:cancelBlock];

  void (^movedBlock)(FDataSnapshot *, NSString *) = ^(FDataSnapshot *snapshot, NSString *prevKey) {
    listener->OnChildMoved(toMojoSnapshot(snapshot), prevKey.UTF8String);
  };
  FirebaseHandle movedHandle = [client_ observeEventType:FEventTypeChildMoved
                          andPreviousSiblingKeyWithBlock:movedBlock
                                         withCancelBlock:cancelBlock];

  void (^removedBlock)(FDataSnapshot *snapshot) = ^(FDataSnapshot *snapshot) {
    listener->OnChildRemoved(toMojoSnapshot(snapshot));
  };
  FirebaseHandle removedHandle = [client_ observeEventType:FEventTypeChildRemoved
                                                 withBlock:removedBlock
                                           withCancelBlock:cancelBlock];

  ptr.set_connection_error_handler(
    [this, addedHandle, changedHandle, movedHandle, removedHandle, listener]() {
      [client_ removeObserverWithHandle:addedHandle];
      [client_ removeObserverWithHandle:changedHandle];
      [client_ removeObserverWithHandle:movedHandle];
      [client_ removeObserverWithHandle:removedHandle];
      auto it = std::find_if(child_event_listeners_.begin(),
                             child_event_listeners_.end(),
                             [listener](const ::firebase::ChildEventListenerPtr& p) {
                               return (p.get() == listener);
                             });
      child_event_listeners_.erase(it);
    }
  );
  child_event_listeners_.emplace_back(ptr.Pass());
}

void FirebaseImpl::ObserveSingleEventOfType(
    ::firebase::EventType eventType,
    const ObserveSingleEventOfTypeCallback& callback) {
  ObserveSingleEventOfTypeCallback *copyCallback =
    new ObserveSingleEventOfTypeCallback(callback);
  [client_ observeSingleEventOfType:static_cast<FEventType>(eventType)
                          withBlock:^(FDataSnapshot *snapshot) {
    copyCallback->Run(toMojoSnapshot(snapshot));
    delete copyCallback;
  }];
}

void FirebaseImpl::AuthWithCustomToken(
  const mojo::String& token,
  const AuthWithCustomTokenCallback& callback) {
}

void FirebaseImpl::AuthAnonymously(
  const AuthAnonymouslyCallback& callback) {
  AuthAnonymouslyCallback *copyCallback =
    new AuthAnonymouslyCallback(callback);
  [client_ authAnonymouslyWithCompletionBlock:^(NSError *error, FAuthData *authData) {
    copyCallback->Run(toMojoError(error), toMojoAuthData(authData));
    delete copyCallback;
  }];
}

void FirebaseImpl::AuthWithOAuthToken(
  const mojo::String& provider,
  const mojo::String& credentials,
  const AuthWithOAuthTokenCallback& callback) {
  AuthWithOAuthTokenCallback *copyCallback =
    new AuthWithOAuthTokenCallback(callback);
  [client_ authWithOAuthProvider:@(provider.data())
                           token:@(credentials.data())
             withCompletionBlock:^(NSError *error, FAuthData *authData) {
    copyCallback->Run(toMojoError(error), toMojoAuthData(authData));
    delete copyCallback;
  }];
}

void FirebaseImpl::AuthWithPassword(
  const mojo::String& email,
  const mojo::String& password,
  const AuthWithPasswordCallback& callback) {
  AuthWithPasswordCallback *copyCallback =
    new AuthWithPasswordCallback(callback);
  [client_      authUser:@(email.data())
                password:@(password.data())
     withCompletionBlock:^(NSError *error, FAuthData *authData) {
    copyCallback->Run(toMojoError(error), toMojoAuthData(authData));
    delete copyCallback;
  }];
}

void FirebaseImpl::Unauth(const UnauthCallback& callback) {
  [client_ unauth];
  callback.Run(toMojoError(nullptr));
}

void FirebaseImpl::GetChild(
    const mojo::String& path,
    mojo::InterfaceRequest<Firebase> request) {
  FirebaseImpl *child = new FirebaseImpl(request.Pass());
  child->client_ = [[client_ childByAppendingPath:@(path.data())] retain];
}

void FirebaseImpl::GetParent(mojo::InterfaceRequest<Firebase> request) {
  FirebaseImpl *parent = new FirebaseImpl(request.Pass());
  parent->client_ = [[client_ parent] retain];
}

void FirebaseImpl::GetRoot(mojo::InterfaceRequest<::firebase::Firebase> request) {
  FirebaseImpl *root = new FirebaseImpl(request.Pass());
  root->client_ = [[client_ root] retain];
}

void FirebaseImpl::SetValue(const mojo::String& jsonValue,
    int32_t priority,
    bool hasPriority,
    const SetValueCallback& callback) {
  SetValueCallback *copyCallback =
    new SetValueCallback(callback);
  NSData *data = [@(jsonValue.data()) dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error;
  NSDictionary *valueDictionary = [NSJSONSerialization JSONObjectWithData:data
                                                                  options:0
                                                                    error:&error];
  id value = [valueDictionary valueForKey:@"value"];
  void (^completionBlock)(NSError *, ::Firebase* ref) = ^(NSError* error, ::Firebase* ref) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  };
  if (valueDictionary != nil) {
    if (hasPriority) {
      [client_     setValue:value
                andPriority:@(priority)
        withCompletionBlock:completionBlock];
    } else {
      [client_ setValue:value withCompletionBlock:completionBlock];
    }
  } else {
    completionBlock(error, client_);
  }
}

void FirebaseImpl::RemoveValue(const RemoveValueCallback& callback) {
  RemoveValueCallback *copyCallback =
    new RemoveValueCallback(callback);
  [client_ removeValueWithCompletionBlock:^(NSError *error, ::Firebase *ref) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

void FirebaseImpl::Push(mojo::InterfaceRequest<Firebase> request,
  const PushCallback& callback) {
  FirebaseImpl *child = new FirebaseImpl(request.Pass());
  child->client_ = [[client_ childByAutoId] retain];
  callback.Run(child->client_.key.UTF8String);
}

void FirebaseImpl::SetPriority(int32_t priority,
  const SetPriorityCallback& callback) {
  SetPriorityCallback *copyCallback =
    new SetPriorityCallback(callback);
  [client_  setPriority:@(priority)
    withCompletionBlock:^(NSError *error, ::Firebase *ref) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

void FirebaseImpl::CreateUser(const mojo::String& email,
  const mojo::String& password,
  const CreateUserCallback& callback) {
  CreateUserCallback *copyCallback =
    new CreateUserCallback(callback);
  [client_   createUser:@(email.data())
               password:@(password.data())
    withValueCompletionBlock:^(NSError *error, NSDictionary *valueDictionary) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:valueDictionary
                                                   options:0
                                                     error:nil];
    if (data != nil) {
      NSString *jsonValue = [[NSString alloc] initWithData:data
                                                  encoding:NSUTF8StringEncoding];
      copyCallback->Run(toMojoError(error), jsonValue.UTF8String);
    } else {
      copyCallback->Run(toMojoError(error), nullptr);
    }
    delete copyCallback;
  }];
}

void FirebaseImpl::ChangeEmail(const mojo::String& oldEmail,
  const mojo::String& password,
  const mojo::String& newEmail,
  const ChangeEmailCallback& callback) {
  ChangeEmailCallback *copyCallback =
    new ChangeEmailCallback(callback);
  [client_ changeEmailForUser:@(oldEmail.data())
                     password:@(password.data())
                   toNewEmail:@(newEmail.data())
          withCompletionBlock:^(NSError *error) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

void FirebaseImpl::ChangePassword(
  const mojo::String& newPassword,
  const mojo::String& email,
  const mojo::String& oldPassword,
  const ChangePasswordCallback& callback) {
  ChangePasswordCallback *copyCallback =
    new ChangePasswordCallback(callback);
  [client_ changePasswordForUser:@(email.data())
                         fromOld:@(oldPassword.data())
                           toNew:@(newPassword.data())
             withCompletionBlock:^(NSError *error) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

void FirebaseImpl::RemoveUser(const mojo::String& email,
  const mojo::String& password,
  const RemoveUserCallback& callback) {
  RemoveUserCallback *copyCallback =
    new RemoveUserCallback(callback);
  [client_  removeUser:@(email.data())
               password:@(password.data())
    withCompletionBlock:^(NSError *error) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

void FirebaseImpl::ResetPassword(const mojo::String& email,
  const ResetPasswordCallback& callback) {
  ResetPasswordCallback *copyCallback =
    new ResetPasswordCallback(callback);
  [client_  resetPasswordForUser:@(email.data())
             withCompletionBlock:^(NSError *error) {
    copyCallback->Run(toMojoError(error));
    delete copyCallback;
  }];
}

}  // namespace firebase

void FlutterServicePerform(mojo::ScopedMessagePipeHandle client_handle,
                           const mojo::String& service_name) {
  if (service_name == firebase::Firebase::Name_) {
    new firebase::FirebaseImpl(
        mojo::MakeRequest<firebase::Firebase>(client_handle.Pass()));
    return;
  }
}

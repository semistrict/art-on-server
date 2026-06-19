/*
 * Copyright (C) 2015 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef ART_RUNTIME_MIRROR_ACCESSIBLE_OBJECT_H_
#define ART_RUNTIME_MIRROR_ACCESSIBLE_OBJECT_H_

#include "base/macros.h"
#include "object.h"
#include "read_barrier_option.h"

namespace art HIDDEN {

namespace mirror {

// C++ mirror of java.lang.reflect.AccessibleObject
class MANAGED AccessibleObject : public Object {
 public:
  MIRROR_CLASS("Ljava/lang/reflect/AccessibleObject;");

  static MemberOffset FlagOffset() {
    return OFFSET_OF_OBJECT_MEMBER(AccessibleObject, flag_);
  }

  bool IsAccessible() REQUIRES_SHARED(Locks::mutator_lock_) {
    return GetFieldBoolean(FlagOffset());
  }

 private:
  // We only use the field indirectly using the FlagOffset() method.
  [[maybe_unused]] uint8_t flag_;

  // art-host fork (large heap): native-pointer-width (8-byte) reference fields
  // in subclasses (e.g. Executable::declaring_class_) must be 8-aligned, which
  // the field linker guarantees by rounding this class's instance size up to the
  // object alignment. Without this explicit padding the packed C++ layout lets a
  // subclass reuse this class's tail padding and place an 8-byte reference at an
  // unaligned offset (here 17 instead of 24), diverging from the field linker and
  // corrupting reference reads. Materialise the rounding as explicit fields so
  // subclass fields begin 8-aligned and the C++ struct matches the field linker.
  [[maybe_unused]] uint8_t padding_[sizeof(uintptr_t) - sizeof(uint8_t)];

  DISALLOW_IMPLICIT_CONSTRUCTORS(AccessibleObject);
};

}  // namespace mirror
}  // namespace art

#endif  // ART_RUNTIME_MIRROR_ACCESSIBLE_OBJECT_H_

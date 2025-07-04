# make /etc/machine-id file empty and shutdown your VM
# enter esxi SSH
# cd /vmfs/volumes/your-volume-name-here

my_template_name="your-template-vm-name-here"
my_template_name_copy="$my_template_name"_copy
copy_count=30
i=1
while [ $i -le $copy_count ]; do
  # Create directory for new VM
  mkdir -p "$my_template_name_copy$i"
  
  # Copy all files except the large -flat.vmdk
  for file in "$my_template_name"/*; do
    [ -f "$file" ] && [ "$file" != "$my_template_name/$my_template_name-flat.vmdk" ] && [ "$file" != "$my_template_name/$my_template_name.vmdk" ] && \
      cp "$file" "$my_template_name_copy$i/"
  done
  
  # Create thin-provisioned clone of the disk
  echo "begin thin-provisioned clone of $my_template_name_copy$i"
  vmkfstools -i "$my_template_name/$my_template_name.vmdk" \
             "$my_template_name_copy$i/$my_template_name.vmdk" \
             -d thin
  echo "end thin-provisioned clone of $my_template_name_copy$i"

  # Modify VMX file to ensure uniqueness
  echo "Modifying VMX configuration for copy $i"
  vmx_file="$my_template_name_copy$i/$my_template_name.vmx"
  
  # 1. Update display name
  sed -i "/^displayName =/d" "$vmx_file"
  echo "displayName = \"$my_template_name_copy$i\"" >> "$vmx_file"
  
  # 2. Remove any existing UUIDs to force generation of new ones
  sed -i "/^uuid\./d" "$vmx_file"
  sed -i "/^vc\.uuid/d" "$vmx_file"
  sed -i "/^bios\.uuid/d" "$vmx_file"
  
  # 3. Remove any existing MAC addresses and generate new ones
  sed -i "/^ethernet[0-9]\.address/d" "$vmx_file"
  sed -i "/^ethernet[0-9]\.addressType/d" "$vmx_file"
  
  # 4. Change the virtualHW.version to ensure new identifiers are generated
  sed -i "/^virtualHW\.version/d" "$vmx_file"
  echo "virtualHW.version = \"19\"" >> "$vmx_file"
  
  # 5. Change the vmdk reference in the vmx file
  sed -i "s/$my_template_name-/$my_template_name_copy$i-/g" "$vmx_file"
  
  # Register the new VM (with full path verification)
  echo "begin register $my_template_name_copy$i"
  vmx_path="$(pwd)/$my_template_name_copy$i/$my_template_name.vmx"
  
  if [ -f "$vmx_path" ]; then
    # Unregister any existing VM with the same name first
    vim-cmd vmsvc/getallvms | grep "$my_template_name_copy$i" && \
      vim-cmd vmsvc/unregister $(vim-cmd vmsvc/getallvms | grep "$my_template_name_copy$i" | awk '{print $1}')
    
    vim-cmd solo/registervm "$vmx_path"
    echo "Successfully registered $my_template_name_copy$i"
  else
    echo "ERROR: VMX file not found at $vmx_path"
    ls -la "$my_template_name_copy$i/"
  fi
  
  echo "end register $my_template_name_copy$i"

  i=$((i+1))
done

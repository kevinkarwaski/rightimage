class Chef::Resource::Bash
  include RightScale::RightImage::Helper
end
class Chef::Resource::RubyBlock
  include RightScale::RightImage::Helper
end
class Chef::Recipe
  include RightScale::RightImage::Helper
end
class Chef::Resource::Execute
  include RightScale::RightImage::Helper
end


# Clean up guest image
rightimage guest_root do
  action :sanitize
end

# bundle and upload
bash "bundle_upload_s3_image" do 
    only_if { node[:rightimage][:cloud] == "ec2" }
    code <<-EOH
#!/bin/bash -ex
    set -e
    set -x

    . /etc/profile
    
    export JAVA_HOME=/usr
    export PATH=$PATH:/usr/local/bin:/home/ec2/bin
    export EC2_HOME=/home/ec2

    umount "#{guest_root}/proc" || true
    
    kernel_opt=""
    if [ -n "#{node[:rightimage][:aki_id]}" ]; then
      kernel_opt="--kernel #{node[:rightimage][:aki_id]}"
    fi 

    ramdisk_opt=""
    if [ -n "#{node[:rightimage][:ramdisk_id]}" ]; then
      ramdisk_opt="--ramdisk #{node[:rightimage][:ramdisk_id]}"
    fi

    #create keyfiles for bundle
    echo "#{node[:rightimage][:aws_509_key]}" > /tmp/AWS_X509_KEY.pem
    echo "#{node[:rightimage][:aws_509_cert]}" > /tmp/AWS_X509_CERT.pem

    echo "Doing S3 bundle"
  
    rm -rf "#{guest_root}"_temp
    mkdir -p "#{guest_root}"_temp

    echo "Bundling..."
    /home/ec2/bin/ec2-bundle-image --privatekey /tmp/AWS_X509_KEY.pem --cert /tmp/AWS_X509_CERT.pem --user #{node[:rightimage][:aws_account_number]} --image #{target_raw_path} --prefix #{image_name} --destination "#{guest_root}"_temp --arch #{node[:rightimage][:arch]} $kernel_opt $ramdisk_opt -B "ami=sda1,root=/dev/sda1,ephemeral0=sdb,swap=sda3"
   
    echo "Uploading..." 
    echo y | /home/ec2/bin/ec2-upload-bundle -b #{node[:rightimage][:image_upload_bucket]} -m "#{guest_root}"_temp/#{image_name}.manifest.xml -a #{node[:rightimage][:aws_access_key_id]} -s #{node[:rightimage][:aws_secret_access_key]} --retry --batch
    
    echo registering... 
    image_out_s3=`/home/ec2/bin/ec2-register #{node[:rightimage][:image_upload_bucket]}/#{image_name}.manifest.xml -K  /tmp/AWS_X509_KEY.pem -C  /tmp/AWS_X509_CERT.pem -n "#{image_name}" --url #{node[:rightimage][:ec2_endpoint]} `

    ## parse out image id
    image_id_s3=`echo -n $image_out_s3 | awk '{ print $2 }'`
    echo "$image_id_s3" > /var/tmp/image_id_s3

    #remove keys
    rm -f /tmp/AWS_X509_KEY.pem
    rm -f /tmp/AWS_X509_CERT.pem

    EOH
end 

ruby_block "store image id" do
  block do
    image_id = nil
    
    # read id which was written in previous stanza
    ::File.open("/var/tmp/image_id_s3", "r") { |f| image_id = f.read() }
    
    # add to global id store for use by other recipes
    id_list = RightImage::IdList.new(Chef::Log)
    id_list.add(image_id)
  end
end


